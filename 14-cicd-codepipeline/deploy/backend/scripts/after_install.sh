#!/bin/bash
# Infrastructure facts (region, DB host, secret ARN) come from Terraform,
# written once per instance by user_data into /etc/three-tier/app.env.
# Application facts (code, version) come from this bundle. The DB password
# itself is fetched fresh from Secrets Manager — never stored in the bundle.
set -euo pipefail

# shellcheck disable=SC1091
source /etc/three-tier/app.env

DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --region "$AWS_REGION" --secret-id "$DB_SECRET_ARN" \
  --query SecretString --output text)
DB_PASSWORD_URLENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$DB_PASSWORD")
VERSION=$(cat /opt/app/backend/VERSION)

cat > /opt/app/backend/.env <<ENV
PORT=3000
NODE_ENV=production
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD_URLENC@$DB_HOST:5432/$DB_NAME
PGSSL=true
PM2_INSTANCES=2
APP_VERSION=$VERSION
ENV
chmod 600 /opt/app/backend/.env

# Idempotent migration; retried because several instances can run it at once.
for attempt in 1 2 3 4 5; do
  if PGSSLMODE=require PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" \
      -v ON_ERROR_STOP=1 -f /opt/app/backend/001_create_search_history.sql; then
    break
  fi
  sleep $((attempt * 3))
done
