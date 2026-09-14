# 03 — Terraform Modules & Security

> Local modules for reuse · a least-privilege IAM policy for the human/CI
> running Terraform · handling secrets with `sensitive`.

## 1. Why modules

Lessons 01/02 each wrote one `aws_instance` block by hand. A three-tier app
needs a bastion, a frontend, and a backend — three near-identical instances
with different names and tags. Copy-pasting the block three times means
three places to fix the same bug later.

A **module** is just a folder of `.tf` files with its own `variables.tf`
(inputs) and `outputs.tf` (return values) — see
[`modules/ec2/`](modules/ec2/). The root [`main.tf`](main.tf) calls it
twice:

```hcl
module "app_a" {
  source        = "./modules/ec2"
  name          = "three-tier-terraform-03-app-a"
  instance_type = "t3.micro"
  extra_tags    = { Lesson = "03-modules-and-security", Role = "app-a" }
}

module "app_b" {
  source        = "./modules/ec2"
  name          = "three-tier-terraform-03-app-b"
  instance_type = "t3.micro"
  extra_tags    = { Lesson = "03-modules-and-security", Role = "app-b" }
}
```

One resource shape, two servers. This is the exact pattern lesson 08 scales
up to bastion/frontend/backend, and lesson 06/07 use for repeating subnet
and security-group shapes across two availability zones.

`source = "./modules/ec2"` is a **local path** module — no registry, no
version pinning needed, just a relative folder. This repo keeps each
lesson's module copy self-contained (rather than pointing every lesson at
one shared root `../../modules/ec2`) so `cd 03-modules-and-security &&
terraform init` always works with nothing outside this folder — the same
"self-contained lesson" rule every folder in this repo follows. The root
[`modules/`](../modules/) directory is the source-of-truth library these
copies are taken from as lessons are built.

## 2. Handling secrets: the `sensitive` flag

[`variables.tf`](variables.tf) declares a variable that's never read by any
resource:

```hcl
variable "demo_secret" {
  type      = string
  default   = "not-a-real-secret"
  sensitive = true
}
```

and [`outputs.tf`](outputs.tf) exposes it:

```hcl
output "demo_secret_redacted" {
  value     = var.demo_secret
  sensitive = true
}
```

Real output from `terraform plan`:

```console
Changes to Outputs:
  + app_a_instance_id    = (known after apply)
  + app_b_instance_id    = (known after apply)
  + demo_secret_redacted = (sensitive value)
```

And after `apply`, `terraform output`:

```console
$ terraform output
app_a_instance_id = "i-016b6807b3d48442f"
app_b_instance_id = "i-06e71a5999355cfd6"
demo_secret_redacted = <sensitive>

$ terraform output -raw demo_secret_redacted
not-a-real-secret
```

**Important limitation**: `sensitive = true` only redacts the CLI's
plan/apply/output console display. The value is still written **in
plaintext** inside `terraform.tfstate` — anyone with read access to the
state file can read it (`terraform output -raw` above proves the value is
trivially recoverable, not encrypted). This is exactly why lesson 04's
remote state uses an S3 bucket with default encryption, and why lesson 08's
real database password goes through AWS Secrets Manager instead of a
Terraform variable at all — Terraform only ever holds a *reference* (the
secret's ARN) in that design, never the password itself.

## 3. A least-privilege IAM policy for running Terraform

Every lesson so far has run under the `ostad` profile, which likely has
broad permissions. In a real team, the human (or CI role) running
`terraform apply` should have exactly the permissions these lessons need —
not `AdministratorAccess`.

[`terraform-runner-policy.json`](terraform-runner-policy.json) is that
policy, scoped to what this specific repo's lessons actually call:

- A **region lock** (`Deny` unless `aws:RequestedRegion` is
  `ap-southeast-1`) as the first statement — one line of defense against a
  mistyped `--region` running up cost/blast-radius somewhere unexpected.
- EC2 create/describe/network actions — necessarily `Resource: "*"` since
  most EC2 network calls (VPC, subnet, route table creation) have no
  resource-level ARN to scope to. This is a real, acknowledged limit of
  IAM's EC2 permission model, not an oversight.
- S3 and DynamoDB actions scoped to `three-tier-terraform-*` names only
  (lesson 04's state bucket/lock table).
- Secrets Manager scoped to the `three-tier-terraform/*` secret name prefix
  (lesson 08).
- IAM actions scoped to `role/three-tier-terraform-*` only, so this policy
  can create instance roles for this project but can't touch any other
  role or user in the account.

This file is **not applied by Terraform** — it's a document you'd attach to
a real IAM user or role by hand (or in a separate, one-time bootstrap
`aws_iam_policy` resource, deliberately out of scope for this lesson so it
never gets torn down along with everything else here).

### Proving it actually works, without creating any IAM resources

`aws iam simulate-custom-policy` evaluates a policy document against real
IAM logic — no resource created, nothing to tear down. Its `policyInputList`
has its own hard 2000-character-per-document cap (unrelated to the real IAM
policy size limit, which is far higher) so the full policy is tested here in
two representative statements — `RegionLock` and `Ec2Full`:

```console
$ aws iam simulate-custom-policy --profile ostad \
    --policy-input-list "$(cat subset-policy.json)" \
    --action-names "ec2:RunInstances" "ec2:DescribeInstances" \
    --resource-arns "*" \
    --context-entries ContextKeyName=aws:RequestedRegion,ContextKeyType=string,ContextKeyValues=ap-southeast-1

--------------------------------------
|        SimulateCustomPolicy        |
+------------------------+-----------+
|  ec2:RunInstances      |  allowed  |
|  ec2:DescribeInstances |  allowed  |
+------------------------+-----------+
```

Now the same call, claiming a request in `us-east-1` instead — proving the
region-lock `Deny` statement actually fires:

```console
$ aws iam simulate-custom-policy --profile ostad \
    --policy-input-list "$(cat subset-policy.json)" \
    --action-names "ec2:RunInstances" \
    --resource-arns "*" \
    --context-entries ContextKeyName=aws:RequestedRegion,ContextKeyType=string,ContextKeyValues=us-east-1

--------------------------------------
|        SimulateCustomPolicy        |
+-------------------+----------------+
|  ec2:RunInstances |  explicitDeny  |
+-------------------+----------------+
```

Exactly the intended behavior: allowed in `ap-southeast-1`, explicitly
denied everywhere else — verified against the real IAM policy evaluation
engine, not just "the JSON parses."

## 4. Run it

```bash
cd 03-modules-and-security
terraform init
terraform plan
terraform apply
```

Real output:

```console
$ terraform apply -auto-approve
module.app_a.aws_instance.this: Creating...
module.app_b.aws_instance.this: Creating...
module.app_a.aws_instance.this: Creation complete after 13s [id=i-016b6807b3d48442f]
module.app_b.aws_instance.this: Creation complete after 13s [id=i-06e71a5999355cfd6]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

Cross-checked with the AWS CLI:

```console
$ aws ec2 describe-instances --profile ostad \
    --instance-ids i-016b6807b3d48442f i-06e71a5999355cfd6 \
    --query 'Reservations[].Instances[].[InstanceId,State.Name,Tags[?Key==`Name`]|[0].Value]' \
    --output text
i-06e71a5999355cfd6    running    three-tier-terraform-03-app-b
i-016b6807b3d48442f    running    three-tier-terraform-03-app-a
```

Both instances exist, both came from the exact same module code.

### Clean up

```console
$ terraform destroy -auto-approve
module.app_b.aws_instance.this: Destruction complete after 20s
module.app_a.aws_instance.this: Destruction complete after 30s

Destroy complete! Resources: 2 destroyed.
```

## If it breaks

- `Error: Module not installed` — run `terraform init` again; it installs
  local modules into `.terraform/modules/` on first init, same as provider
  plugins.
- `Policy input list item 1 has invalid content` from
  `simulate-custom-policy` — that API has a 2000-character-per-item limit;
  pass a trimmed subset of statements, not the full policy file.

## Next

**[04 — Remote State Management (S3)](../04-remote-state-s3/)**
