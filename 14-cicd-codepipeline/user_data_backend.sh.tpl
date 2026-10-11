#!/bin/bash
# Compare with 13-auto-scaling-groups: user_data no longer delivers the app
# at all. It only records the infrastructure facts the app needs — things
# Terraform knows and the pipeline doesn't. The code (and every later
# version of it) arrives through CodeDeploy.
set -euxo pipefail
mkdir -p /etc/three-tier
cat > /etc/three-tier/app.env <<ENV
AWS_REGION=${aws_region}
DB_SECRET_ARN=${db_secret_arn}
DB_HOST=${db_host}
DB_NAME=${db_name}
DB_USER=${db_user}
ENV
chmod 600 /etc/three-tier/app.env
