# three-tier-terraform

Infrastructure as Code for the "Master in DevOps" course — Classes 7 and 8.
This repo recreates the exact architecture built by hand with AWS CLI
shell scripts in [`three-tier-deployment`](https://github.com/ashikMostofaTonmoy/three-tier-deployment),
this time as Terraform: the same Weather Board three-tier app, the same
custom VPC, the same production-ready private/ALB topology — expressed
declaratively instead of as imperative scripts, so the two can be studied
side by side.

Structured after [`terraform-iac-foundations-to-3tier`](https://github.com/sarowar-alam/terraform-iac-foundations-to-3tier):
**one self-contained folder per lesson**, each with its own README, rather
than one giant document — Terraform earns the extra structure.

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI, configured with a profile that can create VPCs/EC2/RDS/IAM/S3/
  Secrets Manager/ELB resources in `ap-southeast-1` (every lesson defaults
  to profile `ostad` — override via `terraform.tfvars`)
- Node.js + npm (lessons 05/08/09/10/11 build the frontend locally via
  `local-exec` before uploading it)
- An SSH client (lesson 10 uses it for real)

## Cost and cleanup — read this first

**Every lesson ends with `terraform destroy`.** Lessons from `06` onward
provision a NAT Gateway (~$0.05/hr), and lessons `08`+ add RDS (~$0.017/hr
for `db.t3.micro`) and an ALB (~$0.0225/hr) — none of it expensive for the
time it takes to work through one lesson, but none of it free either.
**Never leave a lesson applied longer than you're actively using it.**

`04-remote-state-s3/bootstrap/` is the one exception — an S3 bucket and
DynamoDB table shared by every lesson from `04` onward. Create it once,
keep it until every other lesson is destroyed, then tear it down last (see
[lesson 11's README](11-complete-production-deployment/README.md#5-clean-up--including-the-bootstrap-for-the-first-time)).

## Lessons

### Class 7 — Terraform Fundamentals

| # | Lesson | What it covers |
|---|---|---|
| [01](01-terraform-fundamentals/) | Terraform Fundamentals | IaC vs. shell scripts, the init/plan/apply/destroy workflow, your first EC2 instance |
| [02](02-github-copilot-for-terraform/) | Writing Terraform with GitHub Copilot | A real before/after session — what Copilot gets wrong by default (security groups open to the world) and a review checklist |
| [03](03-modules-and-security/) | Terraform Modules & Security | Local modules, the `sensitive` flag and its real limits, a least-privilege IAM policy for whoever runs `terraform apply` |
| [04](04-remote-state-s3/) | Remote State Management | S3 backend + DynamoDB locking, bootstrapped once, proven with a real concurrent-apply lock conflict |
| [05](05-complete-infra-provisioning/) | Complete Infrastructure Provisioning | **Class 7 capstone** — the full single-VM three-tier app (Secrets Manager, `user_data`, S3-staged build artifacts), recreating `three-tier-deployment` Part 2 |

### Class 8 — Recreate the Production-Ready 3-Tier VPC with Terraform

| # | Lesson | What it covers |
|---|---|---|
| [06](06-vpc-networking/) | VPC Networking | 6 subnets, 2 AZs, 3 tiers, one NAT Gateway — Terraform's version of `three-tier-deployment`'s Part 5/6 VPC |
| [07](07-security-groups-as-code/) | Security Groups as Code | The alb→frontend→backend→db chain, and why it destroys cleanly where the original shell-script version needed a manual workaround |
| [08](08-three-tier-deployment/) | Three-Tier Deployment | Frontend + backend on separate instances, Postgres replaced by RDS, across the custom VPC |
| [09](09-load-balancer-target-groups/) | Load Balancer and Target Groups | The frontend goes fully private; the ALB becomes the only public entry point |
| [10](10-bastion-host/) | Bastion Host | A real Terraform-generated SSH key pair, `ProxyJump` to private instances, proven alongside (not instead of) SSM |
| [11](11-complete-production-deployment/) | Complete Production Deployment | **Class 8 capstone** — everything from 06-10 in one `apply`, full state/outputs walkthrough, final teardown including the bootstrap |

## Repo layout

```
three-tier-terraform/
├── frontend/, backend/, database/    the same Weather Board app as three-tier-deployment
├── modules/                          shared source-of-truth library (vpc, security-group,
│                                      ec2, rds, secrets, iam, alb)
├── 01-terraform-fundamentals/ .. 11-complete-production-deployment/
│   └── modules/                      each lesson's own COPY of whichever modules it needs —
│                                      cd in, terraform init, and it works with nothing
│                                      outside that folder
```

Every lesson folder is self-contained on purpose: its own `main.tf`,
`variables.tf`, `outputs.tf`, `terraform.tfvars.example`, and (from lesson
04 on) `backend.hcl.example`. Module copies are point-in-time snapshots
from `modules/`, not symlinks — a student in lesson 06 shouldn't need to
understand the whole library to run one lesson.

## Every command in every lesson's README was actually run

Same standard as `three-tier-deployment`: every `terraform plan`/`apply`/
`destroy` output shown is real, captured against AWS profile `ostad` in
`ap-southeast-1`, cross-checked with raw `aws` CLI calls (not just trusted
from Terraform's own exit code), and torn down afterward. Several lessons'
READMEs document real bugs hit and fixed along the way — an empty security
group ID list Terraform refuses to reconcile (lesson 04), a non-ASCII
character AWS's API silently rejects (lesson 05), a password character
that breaks a connection-string URL parser (lesson 05), a redundant
`sslmode` query param that fights an explicit SSL option (lesson 08), and
a `count` argument that can't depend on a value unknown until apply
(lesson 10) — left in place rather than edited away, because seeing what
actually broke and how it got fixed is worth more than a README that never
shows a single error.
