# three-tier-terraform

Infrastructure as Code for the "Master in DevOps" course: Terraform fundamentals, the production 3-tier VPC as code, Auto Scaling, and CI/CD to Auto Scaling Groups.
This repo recreates the exact architecture built by hand with AWS CLI
shell scripts in [`three-tier-deployment`](https://github.com/ashikMostofaTonmoy/three-tier-deployment),
this time as Terraform: the same Weather Board three-tier app, the same
custom VPC, the same production-ready private/ALB topology — expressed
declaratively instead of as imperative scripts, so the two can be studied
side by side.

Structured after [`terraform-iac-foundations-to-3tier`](https://github.com/sarowar-alam/terraform-iac-foundations-to-3tier):
**one self-contained folder per lesson**, each with its own README, rather
than one giant document — Terraform earns the extra structure.

## Start here (new students)

1. **Find today's topic** in [Lessons](#lessons) below. Each topic lists
   its lesson folders, and its **syllabus map** shows exactly which folder
   and section covers each item of the class outline.
2. **Check the prerequisites** below once, and create the shared Terraform
   state bucket once: [`04-remote-state-s3/bootstrap`](04-remote-state-s3/)
   (every lesson from `04` on stores its state there).
3. **Work one lesson folder at a time**, in number order. Each folder is
   self-contained: `cd` in, read its `README.md`, then
   `terraform init` → `plan` → `apply`. Every README shows the real output
   to expect and has an **"If it breaks"** section at the end.
4. **Some lessons depend on an earlier one still being applied** — the
   README says so at the top of its "Run it" section. The only ones:
   `13`, `14` and `15` need lesson `12`'s AMI.
5. **Clean up at the end of every session** — see
   [Cleaning up after every class](#cleaning-up-after-every-class). One
   command does it: `bash scripts/cleanup-everything.sh --yes`.

Every command in every README was run against a real AWS account; where
something could *not* be verified, the README says so in a
**Verification status** box at the top.

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI, configured with a profile that can create VPCs/EC2/RDS/IAM/S3/
  Secrets Manager/ELB resources in `ap-southeast-1` (every lesson defaults
  to profile `ostad` — override via `terraform.tfvars`)
- Node.js + npm (lessons 05 and 08-14 build the frontend locally)
- An SSH client (lesson 10 uses it for real)
- For the CI/CD lessons: your own **fork** of this repo on GitHub, and the
  [GitHub CLI](https://cli.github.com/) (`gh`) logged in

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

Lessons `12` and `13` add one more ordering rule: lesson 13 launches every
instance from the AMI lesson 12 bakes, so destroy **13, then 12, then the
bootstrap**. Lesson 13 runs ~US$0.16/hour (NAT, RDS, ALB, four instances).

## Cleaning up after every class

Do this at the end of **every** session — a forgotten NAT Gateway + RDS +
ALB is ~US$4/day, every day, until someone notices.

### 1. The normal way — `terraform destroy`, newest lesson first

```bash
cd 15-github-actions-asg          && terraform destroy   # whichever lessons you applied,
cd ../14-cicd-codepipeline        && terraform destroy   # newest first
cd ../13-auto-scaling-groups      && terraform destroy
cd ../12-golden-ami               && terraform destroy   # after 13/14/15 — they launch from its AMI
cd ../14-cicd-codepipeline/github-connection && terraform destroy   # optional: keeps you from re-approving next time
cd ../../04-remote-state-s3/bootstrap && terraform destroy  # ALWAYS LAST — see below
```

Order matters for two reasons:

- **Dependencies across lessons.** Lessons 13-15 launch instances from
  lesson 12's AMI — destroy them first.
- **The state bucket goes last, always.** Every lesson from 04 on keeps its
  Terraform state in `three-tier-terraform-state-<account-id>`. Delete that
  bucket while resources still exist and Terraform loses track of them:
  `terraform destroy` can no longer remove what it no longer knows about,
  and they keep billing. (This happened during the CI/CD lessons — the
  bucket was emptied and deleted from the console with a full stack still
  running. Step 2 is how it was cleaned up.)

The bootstrap bucket is versioned, so `terraform destroy` on it fails
until every object version is gone — see
[lesson 11 §5](11-complete-production-deployment/README.md#5-clean-up--including-the-bootstrap-for-the-first-time),
or just use step 2.

### 2. The safety net — one script, no state needed

[`scripts/cleanup-everything.sh`](scripts/cleanup-everything.sh) finds
every resource this course creates **by name/tag** (`three-tier-terraform*`
/ `three-tier-tf*`) and deletes it in dependency order — Auto Scaling
groups first (or they'd relaunch what you terminate), then load balancers,
RDS, instances, NAT Gateways, then target groups, launch templates,
security groups (rules revoked first, so chained groups don't block each
other), VPCs, AMIs + snapshots, secrets, alarms, IAM roles, the GitHub
connection, S3 buckets (every version emptied), and the lock table.

```bash
bash scripts/cleanup-everything.sh            # DRY RUN — lists what it would delete, deletes nothing
bash scripts/cleanup-everything.sh --yes      # delete it all
# also delete lesson 15's GitHub repo variables and the account-wide GitHub OIDC provider:
bash scripts/cleanup-everything.sh --yes --github-repo your-user/three-tier-terraform --include-github-oidc
bash scripts/cleanup-everything.sh            # run the dry run again: it should list nothing
```

Use it when:

- you're not sure which lessons are still applied,
- Terraform state is gone or broken (deleted bucket, lost laptop, half-failed destroy),
- you just want **one command at the end of class**.

`--include-github-oidc` is opt-in because an AWS account can hold only one
GitHub OIDC provider, and other projects in the same account may rely on it.
Uses `AWS_PROFILE` (default `ostad`) and `AWS_REGION` (default
`ap-southeast-1`); run it from Git Bash on Windows or any Linux/macOS shell.

### 3. Verify — trust the account, not the tool

```bash
aws autoscaling describe-auto-scaling-groups --query 'length(AutoScalingGroups)'
aws ec2 describe-nat-gateways --filter Name=state,Values=available --query 'length(NatGateways)'
aws rds describe-db-instances --query 'length(DBInstances)'
aws elbv2 describe-load-balancers --query 'length(LoadBalancers)'
aws ec2 describe-instances --filters Name=instance-state-name,Values=running,stopped --query 'length(Reservations)'
```

All `0` (assuming nothing else lives in the account) means nothing is billing.

## Lessons

### Terraform Fundamentals

| # | Lesson | What it covers |
|---|---|---|
| [01](01-terraform-fundamentals/) | Terraform Fundamentals | IaC vs. shell scripts, the init/plan/apply/destroy workflow, your first EC2 instance |
| [02](02-github-copilot-for-terraform/) | Writing Terraform with GitHub Copilot | A real before/after session — what Copilot gets wrong by default (security groups open to the world) and a review checklist |
| [03](03-modules-and-security/) | Terraform Modules & Security | Local modules, the `sensitive` flag and its real limits, a least-privilege IAM policy for whoever runs `terraform apply` |
| [04](04-remote-state-s3/) | Remote State Management | S3 backend + DynamoDB locking, bootstrapped once, proven with a real concurrent-apply lock conflict |
| [05](05-complete-infra-provisioning/) | Complete Infrastructure Provisioning | **Fundamentals capstone** — the full single-VM three-tier app (Secrets Manager, `user_data`, S3-staged build artifacts), recreating `three-tier-deployment` Part 2 |

**Syllabus map — Terraform Fundamentals**

| Topic | Where it's taught |
|---|---|
| Introduction to Infrastructure as Code (IaC) | [01](01-terraform-fundamentals/) §1 |
| Introduction to Terraform and setup | [01](01-terraform-fundamentals/) §2 |
| Terraform Architecture and Workflow | [01](01-terraform-fundamentals/) §3 |
| First EC2 Instance with Terraform | [01](01-terraform-fundamentals/) §4 |
| Write Terraform scripts using GitHub Copilot | [02](02-github-copilot-for-terraform/) |
| Terraform Modules & Security | [03](03-modules-and-security/) |
| Remote State Management (S3) | [04](04-remote-state-s3/) |
| Complete Infrastructure Provisioning with Terraform | [05](05-complete-infra-provisioning/) |

### Recreate the Production-Ready 3-Tier VPC with Terraform

| # | Lesson | What it covers |
|---|---|---|
| [06](06-vpc-networking/) | VPC Networking | 6 subnets, 2 AZs, 3 tiers, one NAT Gateway — Terraform's version of `three-tier-deployment`'s Part 5/6 VPC |
| [07](07-security-groups-as-code/) | Security Groups as Code | The alb→frontend→backend→db chain, and why it destroys cleanly where the original shell-script version needed a manual workaround |
| [08](08-three-tier-deployment/) | Three-Tier Deployment | Frontend + backend on separate instances, Postgres replaced by RDS, across the custom VPC |
| [09](09-load-balancer-target-groups/) | Load Balancer and Target Groups | The frontend goes fully private; the ALB becomes the only public entry point |
| [10](10-bastion-host/) | Bastion Host | A real Terraform-generated SSH key pair, `ProxyJump` to private instances, proven alongside (not instead of) SSM |
| [11](11-complete-production-deployment/) | Complete Production Deployment | **Production VPC capstone** — everything from 06-10 in one `apply`, full state/outputs walkthrough, final teardown including the bootstrap |

**Syllabus map — Production-Ready 3-Tier VPC with Terraform**

| Topic | Where it's taught |
|---|---|
| Using Terraform modules for deploying multiple resources | [08](08-three-tier-deployment/) (vpc, rds, secrets, iam, ec2 modules together), [11](11-complete-production-deployment/) §1 |
| Creating VPC, Subnets, and Networking with Terraform | [06](06-vpc-networking/) |
| Deploying the Three-Tier Application with Terraform | [08](08-three-tier-deployment/) |
| Load Balancer and Target Groups with Terraform | [09](09-load-balancer-target-groups/) |
| Security Groups as Code | [07](07-security-groups-as-code/) |
| Bastion Host for secure SSH access | [10](10-bastion-host/) |
| Managing Terraform State and Outputs | [04](04-remote-state-s3/) (remote state), [11](11-complete-production-deployment/) §3 (state list / outputs walkthrough) |

### Auto Scaling for 3-Tier Applications (High Availability & Self-Healing)

| # | Lesson | What it covers |
|---|---|---|
| [12](12-golden-ami/) | Golden AMI from an Existing Instance | Builder EC2 → wait for it to power off → `aws_ami_from_instance`. Runtime-only image (Node, PM2, Nginx, AWS CLI, CodeDeploy agent), and why not to bake app code in |
| [13](13-auto-scaling-groups/) | Auto Scaling Groups | Launch templates, backend + frontend ASGs across 2 AZs, ALB path routing, ELB health checks, self-healing (instance killed / app killed), target tracking vs. step scaling under real load, instance refresh to roll a new AMI with zero failed requests |

**Syllabus map — Auto Scaling for 3-Tier Applications**

| Topic | Where it's taught |
|---|---|
| Why Auto Scaling is Mandatory in Production | [13](13-auto-scaling-groups/) §1 |
| Auto Scaling Architecture for the Three-Tier App | [13](13-auto-scaling-groups/) §2 |
| Creating AMI from Existing Application | [12](12-golden-ami/) (all) |
| Launch Templates Configuration | [13](13-auto-scaling-groups/) §3 |
| Convert Backend EC2 into Auto Scaling Group | [13](13-auto-scaling-groups/) §3 ("Converting the backend…" table) |
| Health Checks & Self-Healing Mechanisms | [13](13-auto-scaling-groups/) §5 |
| Scaling Policies (Target Tracking, Step Scaling) | [13](13-auto-scaling-groups/) §6 |
| (Optional) Frontend Auto Scaling Group | [13](13-auto-scaling-groups/) §3 + §6.2 — skip by deleting `module "frontend_asg"` and keeping a single frontend as in [11](11-complete-production-deployment/) |
| Load Balancer Integration with Auto Scaling | [13](13-auto-scaling-groups/) §2 (path routing, `target_group_arns`) |
| Update Terraform Code for Auto Scaling Groups | [13](13-auto-scaling-groups/) §3 (`modules/asg`) |
| Managing Auto Scaling with Infrastructure as Code | [13](13-auto-scaling-groups/) §6.3 (`ignore_changes`) + §7 (instance refresh) |

### CI/CD with AWS CodePipeline — Deploying to Auto Scaling Groups

| # | Lesson | What it covers |
|---|---|---|
| [14](14-cicd-codepipeline/) | CI/CD with AWS CodePipeline | GitHub → CodePipeline → CodeBuild → CodeDeploy into both ASGs, all as Terraform. One-at-a-time in-place deploys with traffic control, automatic deploy to new ASG instances, automatic rollback of a deliberately broken release. *Verification status: CodeDeploy side verified live; CodeBuild stage blocked by an AWS account limit — see its README §3.* |
| [15](15-github-actions-asg/) | Deploy with GitHub Actions only | No AWS CI/CD services: GitHub Actions + OIDC (no stored keys) → S3 releases → ASG instance refresh, launch-before-terminate. Rollback by re-pointing to an older release |

**Syllabus map — CI/CD with AWS CodePipeline**

| Topic | Where it's taught |
|---|---|
| CI/CD Challenges with Auto Scaling Groups | [14](14-cicd-codepipeline/) §1 |
| CI/CD Architecture for the Three-Tier App | [14](14-cicd-codepipeline/) §2 |
| Create CI/CD Pipeline for Backend Auto Scaling Group | [14](14-cicd-codepipeline/) §3 (`pipeline.tf`, `deploy/`) + §4 |
| Blue/Green Deployment Strategy | Concept and why it's needed: [14](14-cicd-codepipeline/) §5.3. *Hands-on lesson not in the repo yet.* |
| Auto-Deploy to New Instances in Auto Scaling Group | [14](14-cicd-codepipeline/) §5.2 (CodeDeploy lifecycle hook); [15](15-github-actions-asg/) §2 (boot `current/`) |
| CI/CD for Frontend Auto Scaling Group | [14](14-cicd-codepipeline/) §3 (frontend deployment group) |
| Zero-Downtime Deployment Techniques | [14](14-cicd-codepipeline/) §6 (traffic control, draining, one-at-a-time); [15](15-github-actions-asg/) §4-5 (launch-before-terminate) |
| Testing Auto-Scaling Behavior | [14](14-cicd-codepipeline/) §5 (every test is a reproducible exercise, incl. breaking a release on purpose) |
| Automating CI/CD Pipeline Creation with Terraform | [14](14-cicd-codepipeline/) §3; [15](15-github-actions-asg/) §3 (`github.tf`) |
| *Extra:* deploy with GitHub CI/CD only | [15](15-github-actions-asg/) |

## Repo layout

```sh
three-tier-terraform/
├── frontend/, backend/, database/    # the same Weather Board app as three-tier-deployment
├── modules/                          # shared source-of-truth library (vpc, security-group,
│                                      ec2, rds, secrets, iam, alb, alb-path-routing, asg)
├── scripts/cleanup-everything.sh     # delete every course resource in the AWS account
├── .github/workflows/asg-deploy.yml  # lesson 15's GitHub Actions deploy (manual trigger)
├── 01-terraform-fundamentals/ .. 15-github-actions-asg/
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
(lesson 10), a PM2 banner baked into an AMI and an AMI replacement that
would have deregistered the image two ASGs were still launching from
(lesson 12) — left in place rather than edited away, because seeing what
actually broke and how it got fixed is worth more than a README that never
shows a single error.
