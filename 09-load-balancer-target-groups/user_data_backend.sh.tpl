#!/bin/bash
# Rendered by templatefile() in main.tf. Runs in a PRIVATE subnet — reaches
# the internet (for apt/npm/AWS APIs) only through the VPC's NAT Gateway
# (module.vpc, lesson 06), and reaches nothing inbound except the frontend
# (port 3000) and the bastion (port 22, unused until lesson 10) — see the
# security groups in main.tf.
set -euxo pipefail
exec > /var/log/user-data.log 2>&1

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y postgresql-client unzip curl ca-certificates gnupg

curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
npm install -g pm2

DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --region "${aws_region}" \
  --secret-id "${db_secret_arn}" \
  --query SecretString --output text)
DB_PASSWORD_URLENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$DB_PASSWORD")

mkdir -p /opt/app/backend
aws s3 cp "s3://${artifacts_bucket}/${backend_key}" /tmp/backend.zip --region "${aws_region}"
unzip -o -q /tmp/backend.zip -d /opt/app/backend
aws s3 cp "s3://${artifacts_bucket}/${migration_key}" /tmp/migration.sql --region "${aws_region}"

# RDS requires SSL by default (unlike lesson 05's self-managed Postgres) —
# PGSSLMODE covers the psql client here; db.js's own PGSSL=true flag (in
# .env below) covers the Node/pg client.
PGSSLMODE=require PGPASSWORD="$DB_PASSWORD" psql -h "${db_host}" -U "${db_user}" -d "${db_name}" \
  -v ON_ERROR_STOP=1 -f /tmp/migration.sql

cat > /opt/app/backend/.env <<ENV
PORT=3000
NODE_ENV=production
DATABASE_URL=postgresql://${db_user}:$DB_PASSWORD_URLENC@${db_host}:5432/${db_name}
PGSSL=true
PM2_INSTANCES=2
ENV

cd /opt/app/backend
npm ci --omit=dev
pm2 start ecosystem.config.cjs
pm2 startup systemd -u root --hp /root >/dev/null
pm2 save

echo "user_data complete" > /opt/app/DONE
