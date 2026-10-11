#!/bin/bash
set -euxo pipefail
exec > /var/log/user-data.log 2>&1

for i in $(seq 1 24); do
  aws s3api head-object --bucket "${bucket}" --key current/frontend.zip --region "${aws_region}" >/dev/null 2>&1 && break
  sleep 10
done

mkdir -p /opt/app/frontend
aws s3 cp "s3://${bucket}/current/frontend.zip" /tmp/frontend.zip --region "${aws_region}"
unzip -o -q /tmp/frontend.zip -d /opt/app/frontend

cat > /etc/nginx/sites-available/default <<'NGINX'
server {
    listen 80 default_server;
    root /opt/app/frontend;
    index index.html;

    location = /version.txt {
        add_header Cache-Control "no-store";
    }

    location / {
        try_files $uri /index.html;
    }
}
NGINX
nginx -t
systemctl enable --now nginx
systemctl restart nginx
