#!/bin/bash
# Rendered by templatefile() in main.tf. This instance is still in a PUBLIC
# subnet with a public IP — matching three-tier-deployment's Part 5 stage.
# Lesson 09 moves it private and puts an ALB in front, matching Part 6.
set -euxo pipefail
exec > /var/log/user-data.log 2>&1

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx unzip curl ca-certificates gnupg

curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install

mkdir -p /opt/app/frontend
aws s3 cp "s3://${artifacts_bucket}/${frontend_key}" /tmp/frontend.zip --region "${aws_region}"
unzip -o -q /tmp/frontend.zip -d /opt/app/frontend

# The backend lives in a private subnet with no public IP at all — Nginx
# reaches it over the VPC's private network, the only path that exists.
cat > /etc/nginx/sites-available/default <<NGINX
server {
    listen 80 default_server;
    root /opt/app/frontend;
    index index.html;

    location /api/ {
        proxy_pass http://${backend_private_ip}:3000/api/;
        proxy_set_header Host \$host;
    }

    location = /health {
        proxy_pass http://${backend_private_ip}:3000/health;
    }

    location / {
        try_files \$uri /index.html;
    }
}
NGINX
nginx -t
systemctl restart nginx

echo "user_data complete" > /opt/app/DONE
