#!/bin/bash
# Runs on EVERY backend instance the ASG launches — at scale-out, at
# self-healing replacement, at instance refresh. The runtime (Node, PM2,
# AWS CLI, psql) is already in the AMI from lesson 12, so this only does
# the app-specific part: secret, code, config, start.
set -euxo pipefail
exec > /var/log/user-data.log 2>&1

DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --region "${aws_region}" \
  --secret-id "${db_secret_arn}" \
  --query SecretString --output text)
DB_PASSWORD_URLENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$DB_PASSWORD")

mkdir -p /opt/app/backend
aws s3 cp "s3://${artifacts_bucket}/${backend_key}" /tmp/backend.zip --region "${aws_region}"
unzip -o -q /tmp/backend.zip -d /opt/app/backend
aws s3 cp "s3://${artifacts_bucket}/${migration_key}" /tmp/migration.sql --region "${aws_region}"

# Two instances boot at the same moment on first apply and both run this
# migration. It's idempotent (CREATE ... IF NOT EXISTS), but two concurrent
# CREATEs can still collide inside Postgres — so retry instead of failing
# the boot.
for attempt in 1 2 3 4 5; do
  if PGSSLMODE=require PGPASSWORD="$DB_PASSWORD" psql -h "${db_host}" -U "${db_user}" -d "${db_name}" \
      -v ON_ERROR_STOP=1 -f /tmp/migration.sql; then
    break
  fi
  sleep $((attempt * 3))
done

cat > /opt/app/backend/.env <<ENV
PORT=3000
NODE_ENV=production
DATABASE_URL=postgresql://${db_user}:$DB_PASSWORD_URLENC@${db_host}:5432/${db_name}
PGSSL=true
PM2_INSTANCES=2
APP_VERSION=${app_version}
ENV

cd /opt/app/backend
npm ci --omit=dev
pm2 start ecosystem.config.cjs
pm2 startup systemd -u root --hp /root >/dev/null
pm2 save

echo "backend app_version=${app_version}" > /opt/app/DONE
