#!/bin/bash
# Every backend instance boots the CURRENT release: whatever GitHub Actions
# last pointed s3://<bucket>/current/ at. Deploying = publish a release +
# replace instances (instance refresh). Nothing is ever updated in place.
set -euxo pipefail
exec > /var/log/user-data.log 2>&1

# Brand-new stack: no release published yet. Wait for the first workflow
# run (up to 4 minutes, inside the ASG grace period). head-object needs
# only s3:GetObject; `aws s3 ls` would need s3:ListBucket, which this
# role deliberately doesn't have.
for i in $(seq 1 24); do
  aws s3api head-object --bucket "${bucket}" --key current/backend.zip --region "${aws_region}" >/dev/null 2>&1 && break
  sleep 10
done

DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --region "${aws_region}" --secret-id "${db_secret_arn}" \
  --query SecretString --output text)
DB_PASSWORD_URLENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$DB_PASSWORD")

mkdir -p /opt/app/backend
aws s3 cp "s3://${bucket}/current/backend.zip" /tmp/backend.zip --region "${aws_region}"
unzip -o -q /tmp/backend.zip -d /opt/app/backend
VERSION=$(cat /opt/app/backend/VERSION)

for attempt in 1 2 3 4 5; do
  if PGSSLMODE=require PGPASSWORD="$DB_PASSWORD" psql -h "${db_host}" -U "${db_user}" -d "${db_name}" \
      -v ON_ERROR_STOP=1 -f /opt/app/backend/001_create_search_history.sql; then
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
APP_VERSION=$VERSION
ENV
chmod 600 /opt/app/backend/.env

# node_modules ship inside the release (built on GitHub's Linux runner) —
# no npm install at boot.
cd /opt/app/backend
pm2 start ecosystem.config.cjs
pm2 startup systemd -u root --hp /root >/dev/null
pm2 save
