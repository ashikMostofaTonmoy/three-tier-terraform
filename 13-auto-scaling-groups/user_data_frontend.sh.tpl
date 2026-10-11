#!/bin/bash
# Runs on every frontend instance the ASG launches. Nginx is already in the
# AMI (disabled) — this just drops in the current build and turns it on.
# No /api/ proxy here anymore: the ALB routes /api/* to the backend target
# group before a request ever reaches this instance.
set -euxo pipefail
exec > /var/log/user-data.log 2>&1

mkdir -p /opt/app/frontend
aws s3 cp "s3://${artifacts_bucket}/${frontend_key}" /tmp/frontend.zip --region "${aws_region}"
unzip -o -q /tmp/frontend.zip -d /opt/app/frontend

cat > /etc/nginx/sites-available/default <<'NGINX'
server {
    listen 80 default_server;
    root /opt/app/frontend;
    index index.html;

    location / {
        try_files $uri /index.html;
    }
}
NGINX
nginx -t
systemctl enable --now nginx
systemctl restart nginx

echo "frontend app_version=${app_version}" > /opt/app/DONE
