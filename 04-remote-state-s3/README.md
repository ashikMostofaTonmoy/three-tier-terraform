# 04 — Remote State Management (S3)

> Why local `terraform.tfstate` doesn't scale past one laptop · bootstrapping
> an S3 backend + DynamoDB lock table · migrating a lesson to it · proving
> the lock is real.

## 1. The problem with local state

Every lesson so far has a `terraform.tfstate` file sitting next to its
`.tf` files (gitignored — see the root `.gitignore`). That's fine solo, but
breaks the moment more than one person (or a CI pipeline) needs to run
`apply`:

- **No sharing** — a teammate's `terraform plan` has no idea what your
  laptop already created; it would try to create everything again.
- **No locking** — two people running `apply` at the same moment can
  corrupt the state file or, worse, both succeed against AWS while only one
  write survives locally.
- **No durability** — the state file is the only record of what Terraform
  manages. Delete your laptop, lose the state, and Terraform "forgets"
  every resource it created (they still exist in AWS, but now unmanaged).

**Remote state** fixes all three: store `terraform.tfstate` in S3 (shared,
versioned, durable) and use a DynamoDB table to hold a lock while any
`plan`/`apply` is in progress (so two runs can't race).

## 2. Bootstrapping the backend

[`bootstrap/`](bootstrap/) is a special, self-contained mini-config that
creates the S3 bucket and DynamoDB table every *other* lesson's remote
state depends on. It cannot use a remote backend itself — chicken-and-egg —
so **its own state stays local on purpose**, and it's the one config in this
whole repo you run once and never `destroy` until every other lesson is
torn down (see the root README's ordering warning).

```console
$ cd bootstrap
$ terraform init && terraform apply -auto-approve

aws_dynamodb_table.lock: Creating...
aws_s3_bucket.state: Creating...
aws_s3_bucket.state: Creation complete after 3s [id=three-tier-terraform-state-738928894806]
aws_s3_bucket_public_access_block.state: Creation complete after 0s
aws_s3_bucket_server_side_encryption_configuration.state: Creation complete after 1s
aws_s3_bucket_versioning.state: Creation complete after 2s
aws_dynamodb_table.lock: Creation complete after 8s [id=three-tier-terraform-lock]

Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:
aws_region = "ap-southeast-1"
lock_table_name = "three-tier-terraform-lock"
state_bucket_name = "three-tier-terraform-state-738928894806"
```

Note the bucket name embeds the AWS account ID
(`three-tier-terraform-state-738928894806`) — S3 bucket names are globally
unique across *all* AWS accounts, so a fixed name like
`three-tier-terraform-state` would collide with anyone else taking this
course. Verified independently:

```console
$ aws dynamodb describe-table --profile ostad --table-name three-tier-terraform-lock \
    --query 'Table.[TableName,TableStatus,BillingModeSummary.BillingMode]' --output text
three-tier-terraform-lock      ACTIVE  PAY_PER_REQUEST

$ aws s3api get-bucket-versioning --profile ostad --bucket three-tier-terraform-state-738928894806
Enabled

$ aws s3api get-bucket-encryption --profile ostad --bucket three-tier-terraform-state-738928894806
AES256
```

## 3. Pointing a lesson at the remote backend

[`versions.tf`](versions.tf) declares a **partial** backend block:

```hcl
backend "s3" {
  key = "04-remote-state-s3/terraform.tfstate"
}
```

`bucket`/`region`/`dynamodb_table`/`profile` are deliberately left out of
the `.tf` file — they'd hardcode an account-specific bucket name into
version-controlled code. Instead they come from
[`backend.hcl`](backend.hcl.example) (gitignored, same reasoning as
`terraform.tfvars`), passed with `-backend-config`:

```bash
cp backend.hcl.example backend.hcl
# edit backend.hcl: paste in the account ID from the bootstrap outputs above
terraform init -backend-config=backend.hcl
```

Real output:

```console
$ terraform init -backend-config=backend.hcl
Initializing the backend...

Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.
Initializing modules...
- app in modules\ec2
Initializing provider plugins...
- Installing hashicorp/aws v5.100.0...
Terraform has been successfully initialized!
```

## 4. A real bug this lesson surfaced: `[]` vs `null` for security groups

The `ec2` module (copied from lesson 03) originally wrote:

```hcl
vpc_security_group_ids = var.security_group_ids   # default = []
```

First `apply` succeeded — AWS auto-attached the VPC's default security
group since none was specified. But the **second** `plan` against that same
instance showed:

```console
~ vpc_security_group_ids = [
    - "sg-0869edbc0b7610aef",
  ]
Plan: 0 to add, 1 to change, 0 to destroy.
```

and applying it failed outright:

```console
Error: VPC-based instances require at least one security group to be attached.
```

**Why**: an explicit `vpc_security_group_ids = []` tells Terraform "this
instance should have *zero* security groups" — a real desired state it then
tries to enforce by stripping the default SG AWS attached, which AWS's API
flatly rejects. This is exactly the kind of drift that only remote,
re-`plan`-able state catches — a one-shot local `apply` (like lessons 01-03
each did) never ran a second `plan` against the same resource to notice it.

**Fix**, in [`modules/ec2/main.tf`](modules/ec2/main.tf):

```hcl
vpc_security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : null
```

`null` means "don't manage this argument at all" — Terraform leaves
whatever AWS assigned alone. After the fix:

```console
$ terraform plan
No changes. Your infrastructure matches the configuration.
```

## 5. Proving the lock is real

Started a slow `apply` (forcing a replace, so it takes the better part of a
minute) in the background, then immediately ran a second command against
the same state:

```console
$ terraform apply -auto-approve -replace="module.app.aws_instance.this" &
$ terraform plan -lock-timeout=5s

Error: Error acquiring the state lock

Lock Info:
  ID:        55df94b2-798a-7add-b7de-333ced260cb7
  Path:      three-tier-terraform-state-738928894806/04-remote-state-s3/terraform.tfstate
  Operation: OperationTypeApply
  Who:       LAPTOP-V1NVBB98\tonmoy@LAPTOP-V1NVBB98
  Version:   1.14.6
  Created:   2026-09-14 03:04:16 UTC
```

Not a simulated message — a real `ConditionalCheckFailedException` from
DynamoDB's `PutItem`, because the lock row already existed. Confirmed the
row directly while the first apply was still running:

```console
$ aws dynamodb scan --profile ostad --table-name three-tier-terraform-lock
{
    "Items": [
        {
            "LockID": {"S": "three-tier-terraform-state-.../terraform.tfstate"},
            "Info": {"S": "{\"Operation\":\"OperationTypeApply\", ... \"Who\":\"LAPTOP-V1NVBB98\\\\tonmoy...\"}"}
        },
        {
            "LockID": {"S": ".../terraform.tfstate-md5"}
        }
    ]
}
```

Two rows: the active lock (`...tfstate`, only present while a run is in
progress) and a permanent `-md5` checksum row (used to detect state
corruption, always present once state exists). Once the first `apply`
finished, the lock row was gone — only the `-md5` row remained:

```console
$ aws dynamodb scan --profile ostad --table-name three-tier-terraform-lock \
    --query 'Items[].LockID.S' --output text
three-tier-terraform-state-.../terraform.tfstate-md5
```

The first apply also demonstrated lesson 03's `create_before_destroy`
lifecycle for real, since `-replace` forces exactly that path:

```console
module.app.aws_instance.this: Creating...
module.app.aws_instance.this: Creation complete after 13s [id=i-0f24310e7941e497b]
module.app.aws_instance.this (deposed object 023bf745): Destroying... [id=i-0d2beb36324b3d42b]
module.app.aws_instance.this: Destruction complete after 30s

Apply complete! Resources: 1 added, 0 changed, 1 destroyed.
```

The new instance existed before the old one was destroyed — no gap where
neither did.

## 6. Clean up

```console
$ terraform destroy -auto-approve
module.app.aws_instance.this: Destruction complete after 31s
Destroy complete! Resources: 1 destroyed.
```

**Do not destroy `bootstrap/` yet.** Every lesson from here through `11`
uses this same S3 bucket and DynamoDB table. Bootstrap teardown is the
final step of this whole repo — see [lesson 11's README](../11-complete-production-deployment/README.md#5-clean-up--including-the-bootstrap-for-the-first-time)
for how that actually went (short version: the bucket had versioning
enabled, so emptying it before `terraform destroy` would touch it needed
`list-object-versions` + `delete-objects`, not a plain `s3 rm`).

## If it breaks

- `Error: Backend configuration changed` after editing `backend.hcl` —
  re-run `terraform init -backend-config=backend.hcl -reconfigure`.
- `NoSuchBucket` — you copied `backend.hcl.example` without replacing
  `<ACCOUNT_ID>` with the real one from bootstrap's `terraform output`.
- A stuck lock after a crashed `apply` (Ctrl-C mid-run) — confirm no other
  process is actually running, then `terraform force-unlock <LOCK_ID>`
  (the ID is printed in the lock error).

## Next

**[05 — Complete Infrastructure Provisioning (Class 7 capstone)](../05-complete-infra-provisioning/)**
