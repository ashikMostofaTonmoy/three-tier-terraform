# 05 — Complete Infrastructure Provisioning (Class 7 capstone)

> `terraform apply` alone produces the same working Weather Board app that
> `three-tier-deployment`'s Part 2 built with a dozen hand-run shell scripts
> and manual server steps — frontend, backend, and a self-managed Postgres,
> all on one EC2 instance in the default VPC.

## 1. What this recreates, and what's different

This is the same architecture as `three-tier-deployment`'s Part 2: one EC2
instance, Nginx serving the built React frontend and reverse-proxying
`/api/` to a Node/Express backend, backend talking to a local Postgres.
Everything that mattered there still matters here — it's the *provisioning
method* that changes:

| | Part 2 (`three-tier-deployment`) | This lesson |
|---|---|---|
| Create the EC2 instance | `infra/01-ec2.sh` (AWS CLI) | `module "app"` (the `ec2` module, lesson 03) |
| DB password | `openssl rand -hex` into `.env` by hand | `random_password` → AWS Secrets Manager (lesson 03's `sensitive` idea, for real) |
| Deploy the app | `scripts/deploy-*.sh` run manually after the instance exists | `user_data`, runs automatically at first boot |
| State / record of what exists | None — re-read the scripts or check the console | `terraform state list`, backed by S3 (lesson 04) |

## 2. The moving pieces

```mermaid
flowchart TD
    tf["terraform apply"] --> build["local-exec:<br/>npm run build (frontend)"]
    build --> zip["archive_file:<br/>zip frontend/backend/migration.sql"]
    zip --> s3["S3 bucket<br/>(force_destroy = true)"]
    tf --> secret["random_password<br/>→ Secrets Manager"]
    tf --> iam["IAM role: read this ONE secret,<br/>GetObject from this ONE bucket,<br/>+ SSM (no inbound SSH)"]
    tf --> ec2["EC2 instance<br/>(ec2 module)"]
    ec2 -->|"user_data at boot"| boot["installs Postgres/Node/Nginx,<br/>fetches secret + artifacts,<br/>runs migration, starts PM2 + Nginx"]
    s3 -.->|"aws s3 cp"| boot
    secret -.->|"aws secretsmanager get-secret-value"| boot
```

- [`modules/secrets/`](modules/secrets/) — `random_password` → an AWS
  Secrets Manager secret. The password is never a Terraform variable,
  output, or file in this repo — only the secret's **ARN** is passed
  around. See §4 for the honest limits of this.
- [`modules/iam/`](modules/iam/) — one EC2 instance role, scoped to
  `secretsmanager:GetSecretValue` on exactly that one secret ARN and
  `s3:GetObject` on exactly this lesson's artifact bucket, plus
  `AmazonSSMManagedInstanceCore` so the instance is debuggable via
  `aws ssm send-command`/`start-session` with **zero inbound security group
  rules** — no port 22 anywhere in this lesson.
- [`main.tf`](main.tf)'s `null_resource.frontend_build` runs `npm run
  build` locally via `local-exec`, then `archive_file` zips the result —
  Terraform orchestrates the build, it doesn't compile anything itself.
- [`user_data.sh.tpl`](user_data.sh.tpl), rendered by `templatefile()`,
  is the entire Part-2 deploy runbook compressed into one boot-time script:
  install Postgres/Node/Nginx, fetch the DB password, create the app
  role/database, download the three S3 artifacts, run the migration,
  write `.env`, `pm2 start`, configure Nginx.

## 3. Run it

```bash
cd 05-complete-infra-provisioning
cp backend.hcl.example backend.hcl   # fill in your account ID from bootstrap's output
terraform init -backend-config=backend.hcl
terraform apply
```

### Bug #1 (real, hit live): non-ASCII security group description

First `apply` failed partway through:

```console
Error: creating Security Group (three-tier-terraform-05-web-sg): ...
api error InvalidParameterValue: Value (HTTP from anywhere; no inbound
SSH — debugging via SSM only) for parameter GroupDescription is invalid.
Character sets beyond ASCII are not supported.
```

The em-dash (`—`) in the description string is not ASCII. AWS's
`GroupDescription` field silently limits itself to ASCII — an easy trap
for anyone writing Terraform comments/descriptions with the same "nice"
typography used in prose (including every README in this repo). Fixed by
using a plain hyphen (`-`) instead.

### Bug #2 (real, hit live): `#`/`%` in the password broke the DB connection

Once the instance came up, `/health` worked but both API endpoints failed
identically:

```console
$ curl http://<ip>/api/v1/forecast?...
{"error":true,"reason":"Invalid URL"}
$ curl http://<ip>/api/v1/history
{"error":true,"reason":"Invalid URL"}
```

Both endpoints touch Postgres; neither touches a URL directly, so the
common failure pointed at `db.js`. Inspected the backend's own logs via
SSM (no SSH needed — this is exactly what `enable_ssm` in the IAM module
is for):

```console
$ aws ssm send-command --instance-ids i-05f87a58e2f4bbb04 \
    --document-name AWS-RunShellScript \
    --parameters commands='["pm2 logs backend --lines 20 --nostream"]'
...
TypeError: Invalid URL
    at new URL (node:internal/url:806:29)
    at parse (/opt/app/backend/node_modules/pg-connection-string/index.js:30:16)
    at new ConnectionParameters (.../pg/lib/connection-parameters.js:60:42)
```

`pg` parses `DATABASE_URL` with the WHATWG `URL` parser. Lesson 03's
`random_password` module uses `override_special = "!#%^*()-_=+"` — and two
of those characters are special to a URL: `#` starts a fragment (truncating
everything after it), and a lone `%` not followed by two hex digits is an
invalid percent-encoding sequence. Either one, if it landed in the
generated password, breaks the connection string outright. `psql` (used
directly via `PGPASSWORD` for the migration step) has no such restriction —
which is exactly why the migration step succeeded while the app's own
connection failed.

**Fix**, in [`user_data.sh.tpl`](user_data.sh.tpl): percent-encode only the
copy of the password used inside the connection string, leaving the raw
password for everything else (Postgres role creation, `PGPASSWORD`):

```bash
DB_PASSWORD_URLENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$DB_PASSWORD")
...
DATABASE_URL=postgresql://${db_user}:$DB_PASSWORD_URLENC@localhost:5432/${db_name}
```

After the fix (`user_data_replace_on_change = true` on the `ec2` module
meant this alone forced a clean instance replacement — no manual
intervention):

```console
$ terraform apply -auto-approve
module.app.aws_instance.this: Creation complete after 13s [id=i-062c31d084e5b9462]
module.app.aws_instance.this (deposed object ebd79f99): Destroying...
module.app.aws_instance.this: Destruction complete after 30s
Apply complete! Resources: 2 added, 1 changed, 2 destroyed.

Outputs:
app_url = "http://13.212.246.210"
instance_id = "i-062c31d084e5b9462"
```

## 4. Proof it actually works end-to-end

```console
$ curl http://13.212.246.210/health
{"status":"ok"}

$ curl -o /dev/null -w "%{http_code}\n" http://13.212.246.210/
200

$ curl "http://13.212.246.210/api/v1/forecast?latitude=23.81&longitude=90.41&city=Dhaka"
{"latitude":23.796133,"longitude":90.38055,...,"current":{"temperature_2m":...

$ curl http://13.212.246.210/api/v1/history
{"rows":[{"city":"Dhaka","latitude":"23.81000","longitude":"90.41000","temperature":"30.90","queried_at":"2026-09-14T03:19:50.784Z"}]}
```

Real weather data, and the history row proves the request actually reached
Postgres and back — the whole three-tier request path, not just an Nginx
static-file check.

## 5. The honest limits of the Secrets Manager approach

`terraform output` never exposes the password — only its secret ARN:

```console
$ terraform output
db_secret_arn = "arn:aws:secretsmanager:...:secret:three-tier-terraform/05/db-password-vlfrCS"
```

But `random_password`'s result **is** stored in Terraform's state, in
plaintext, regardless — confirmed directly (without printing the value):

```console
$ terraform state pull | python3 -c "
import json,sys
state = json.load(sys.stdin)
print('random_password result present in state:',
      any(r['type']=='random_password' for r in state['resources']))"
random_password result present in state: True
```

This is the same limit lesson 03 flagged for `sensitive` outputs — Secrets
Manager protects the password from ever appearing in a Terraform **output**
or in this repo's source, but the real security boundary is still the
state file itself, which is why it lives in an encrypted, access-controlled
S3 bucket (lesson 04) rather than on a laptop.

## 6. Clean up

```console
$ terraform destroy -auto-approve
Destroy complete! Resources: 15 destroyed.
```

`force_destroy = true` on the artifacts bucket means this also removes the
zipped build artifacts — nothing left behind to clean up by hand.

## If it breaks

- `Error: local-exec provisioner error` on `null_resource.frontend_build` —
  `npm ci` needs `frontend/package-lock.json` present (it is, committed at
  the repo root) and network access from wherever you run `terraform
  apply`.
- Health check never turns green — `user_data` can take 1-2 minutes
  (installing Postgres, Node, and downloading AWS CLI v2). Check
  `/var/log/user-data.log` via SSM if it's still failing after 5 minutes:
  `aws ssm send-command --instance-ids <id> --document-name
  AWS-RunShellScript --parameters commands='["tail -50 /var/log/user-data.log"]'`.
- `Invalid URL` from the API — see Bug #2 above; if you changed
  `override_special` in `modules/secrets/main.tf`, make sure it still
  excludes `#` and doesn't introduce a lone `%`.

## Next

**[06 — VPC Networking (Class 8 begins)](../06-vpc-networking/)**
