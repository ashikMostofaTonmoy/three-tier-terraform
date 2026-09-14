# 02 — Writing Terraform with GitHub Copilot

> This lesson can't be scripted the way the others are — Copilot's actual
> suggestions vary run to run. What follows is a **real, reproducible
> session**: the exact prompts used, what Copilot suggested, what got
> rejected and why, and the resulting HCL — applied for real against AWS to
> prove it works. Treat it as a template for how to *review* AI-generated
> infrastructure code, not as a transcript to memorize.

## 1. Where Copilot helps, and where it doesn't

Terraform's HCL is repetitive and pattern-heavy — exactly what autocomplete
tools are good at: an `aws_security_group` block, a `variable` declaration,
a `tags` map matching the rest of the file. Where it's *not* good: knowing
**what your infrastructure should actually allow**. Copilot doesn't know
your threat model. It pattern-matches on public examples, and public
examples are disproportionately `0.0.0.0/0` — because that's what most
tutorials use to "just get it working."

**Rule for this lesson: read every suggestion before accepting it. A
Terraform diff that overshoots what you asked for is a lot cheaper to reject
in the editor than to notice at 2am after a `describe-security-groups`
audit.**

## 2. Session 1 — declaring a variable

**Prompt (as a comment above an empty line in `variables.tf`):**

```hcl
# variable for the caller's public IP, as a /32 CIDR, no default
```

**Copilot suggested:**

```hcl
variable "my_ip_cidr" {
  description = "Your own public IP, as a /32 CIDR, allowed to SSH into the instance"
  type        = string
}
```

**Accepted as-is.** Correct call by Copilot: no `default` — every student's
IP is different, and a variable like this should fail loudly
(`No value for required variable`) rather than silently default to
something wrong. See [`variables.tf`](variables.tf).

## 3. Session 2 — the security group (the important one)

**Prompt:**

```
security group allowing SSH from my IP and HTTP from anywhere, for a
single EC2 instance
```

**Copilot's first suggestion** (paraphrased from the actual session):

```hcl
resource "aws_security_group" "web" {
  name = "web-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]      # <-- wrong
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

**Rejected the SSH rule.** The prompt explicitly said "from my IP," and the
suggestion still defaulted SSH to the open internet — the exact pattern
flagged in §1. This is the single most common mistake in Copilot-generated
Terraform for AWS: it's seen far more `0.0.0.0/0` example code than
locked-down code, so that's its statistical default. **Never accept a
security-group suggestion without reading every `cidr_blocks` line.**

**Edited manually** to use `var.my_ip_cidr` for the SSH rule, added
`description` fields on every rule (Copilot's draft had none — cheap to add,
makes `describe-security-groups` output self-documenting later), and
descriptive names instead of the generic `web-sg`. Final version in
[`main.tf`](main.tf):

```hcl
resource "aws_security_group" "web" {
  name        = "three-tier-terraform-02-web-sg"
  description = "Allow SSH from my IP and HTTP from anywhere"

  ingress {
    description = "SSH from my IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }
  # ... HTTP + egress unchanged from the suggestion
}
```

## 4. Review checklist for any AI-generated Terraform

Use this on every suggestion, not just security groups:

- [ ] **Every `cidr_blocks`** — is `0.0.0.0/0` actually intended, or did the
      tool default to it?
- [ ] **No hardcoded AMI IDs** — should be a `data "aws_ami"` lookup (an AMI
      ID is a region-specific snapshot pointer that goes stale).
- [ ] **No hardcoded account IDs/ARNs** — should be
      `data.aws_caller_identity.current.account_id` (used from lesson 03
      onward).
- [ ] **Secrets never as plain resource arguments** — a suggested
      `password = "..."` string is a red flag; that value lands in
      `terraform.tfstate` in plaintext regardless (see lesson 04's remote
      state, and lesson 08's Secrets Manager module).
- [ ] **`description` fields present** on security group rules, variables,
      outputs — costs nothing, makes `plan`/CLI output self-explanatory
      months later.
- [ ] **Does the resource actually need what it's asking for** — Copilot
      will happily suggest a `*` IAM policy because it's shorter than a
      scoped one; that's backwards for infrastructure that outlives the
      lesson.

## 5. Run it

```bash
cd 02-github-copilot-for-terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set my_ip_cidr to YOUR public IP
# find it with: curl -s https://checkip.amazonaws.com
terraform init
terraform plan
terraform apply
```

Real session — public IP resolved at the time this was run:

```console
$ curl -s https://checkip.amazonaws.com
43.243.206.116

$ terraform init
Installing hashicorp/aws v5.100.0...
Terraform has been successfully initialized!

$ terraform plan
Plan: 2 to add, 0 to change, 0 to destroy.

$ terraform apply -auto-approve
aws_security_group.web: Creating...
aws_security_group.web: Creation complete after 2s [id=sg-02dcf698262023427]
aws_instance.web: Creating...
aws_instance.web: Still creating... [00m10s elapsed]
aws_instance.web: Creation complete after 13s [id=i-0940c8a799fcb8615]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:
instance_id = "i-0940c8a799fcb8615"
public_ip = "13.251.114.164"
security_group_id = "sg-02dcf698262023427"
```

Cross-checked with the AWS CLI directly — not just trusting Terraform's own
output — to confirm the SSH rule really is scoped to one IP and not
`0.0.0.0/0`:

```console
$ aws ec2 describe-security-groups --profile ostad \
    --group-ids sg-02dcf698262023427 \
    --query 'SecurityGroups[0].IpPermissions' --output json
[
    {
        "IpProtocol": "tcp", "FromPort": 80, "ToPort": 80,
        "IpRanges": [{"Description": "HTTP from anywhere", "CidrIp": "0.0.0.0/0"}]
    },
    {
        "IpProtocol": "tcp", "FromPort": 22, "ToPort": 22,
        "IpRanges": [{"Description": "SSH from my IP only", "CidrIp": "43.243.206.116/32"}]
    }
]
```

Exactly what was intended — port 22 is not open to the world.

### Clean up

```console
$ terraform destroy -auto-approve
aws_instance.web: Destroying... [id=i-0940c8a799fcb8615]
aws_instance.web: Still destroying... [00m20s elapsed]
aws_instance.web: Destruction complete after 20s
aws_security_group.web: Destroying... [id=sg-02dcf698262023427]
aws_security_group.web: Destruction complete after 0s

Destroy complete! Resources: 2 destroyed.
```

## If it breaks

- `Error: No value for required variable "my_ip_cidr"` — you skipped
  `cp terraform.tfvars.example terraform.tfvars`, or forgot to fill it in.
- Your IP changes between `plan` and `apply` (laptop switches networks) —
  re-run `curl -s https://checkip.amazonaws.com`, update `terraform.tfvars`,
  re-plan. Terraform will show an in-place update to the SG rule, not a
  destroy/recreate.

## Next

**[03 — Terraform Modules & Security](../03-modules-and-security/)**
