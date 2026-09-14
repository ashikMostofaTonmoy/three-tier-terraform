#!/bin/bash
# Rendered by Terraform's templatefile() in main.tf — every Terraform
# variable reference below is substituted at plan/apply time.
set -euxo pipefail
exec > /var/log/user-data.log 2>&1

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx postgresql postgresql-contrib unzip curl ca-certificates gnupg

# AWS CLI v2 (the Ubuntu apt package is an old v1 build) — official installer
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
npm install -g pm2

# --- Fetch the DB password Terraform generated (lesson 03's `sensitive`,
# for real this time): the instance's IAM role can read exactly this one
# secret, nothing else in the account.
DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --region "${aws_region}" \
  --secret-id "${db_secret_arn}" \
  --query SecretString --output text)

# --- Postgres: create the app role + database (idempotent on re-runs)
sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${db_user}') THEN
    CREATE ROLE ${db_user} LOGIN PASSWORD '$DB_PASSWORD';
  ELSE
    ALTER ROLE ${db_user} WITH PASSWORD '$DB_PASSWORD';
  END IF;
END
\$\$;
SQL
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = '${db_name}'" | grep -q 1 \
  || sudo -u postgres psql -c "CREATE DATABASE ${db_name} OWNER ${db_user};"

# --- App artifacts, staged to S3 by Terraform (see main.tf's aws_s3_object
# resources) — this instance's IAM role can GetObject only from this bucket.
mkdir -p /opt/app/backend /opt/app/frontend
aws s3 cp "s3://${artifacts_bucket}/${backend_key}" /tmp/backend.zip --region "${aws_region}"
unzip -o -q /tmp/backend.zip -d /opt/app/backend
aws s3 cp "s3://${artifacts_bucket}/${frontend_key}" /tmp/frontend.zip --region "${aws_region}"
unzip -o -q /tmp/frontend.zip -d /opt/app/frontend
aws s3 cp "s3://${artifacts_bucket}/${migration_key}" /tmp/migration.sql --region "${aws_region}"

PGPASSWORD="$DB_PASSWORD" psql -h localhost -U "${db_user}" -d "${db_name}" -v ON_ERROR_STOP=1 -f /tmp/migration.sql

# node-postgres parses DATABASE_URL with the WHATWG URL parser (via
# pg-connection-string), which treats "#" as a fragment delimiter and
# rejects a lone unencoded "%" as invalid percent-encoding — both are in
# random_password's charset (lesson 03's `override_special`). Percent-encode
# just the password for the connection string; psql above used it raw via
# PGPASSWORD, which has no such restriction.
DB_PASSWORD_URLENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$DB_PASSWORD")

cat > /opt/app/backend/.env <<ENV
PORT=3000
NODE_ENV=production
DATABASE_URL=postgresql://${db_user}:$DB_PASSWORD_URLENC@localhost:5432/${db_name}
PM2_INSTANCES=2
ENV

cd /opt/app/backend
npm ci --omit=dev
pm2 start ecosystem.config.cjs
pm2 startup systemd -u root --hp /root >/dev/null
pm2 save

# --- Nginx: serve the built frontend, proxy /api/ to the backend cluster
cat > /etc/nginx/sites-available/default <<'NGINX'
server {
    listen 80 default_server;
    root /opt/app/frontend;
    index index.html;

    location /api/ {
        proxy_pass http://127.0.0.1:3000/api/;
        proxy_set_header Host $host;
    }

    location = /health {
        proxy_pass http://127.0.0.1:3000/health;
    }

    location / {
        try_files $uri /index.html;
    }
}
NGINX
nginx -t
systemctl restart nginx

echo "user_data complete" > /opt/app/DONE
