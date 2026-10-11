#!/bin/bash
# Nginx is configured once per instance; the files it serves arrive through
# CodeDeploy. Until the first deployment lands, / returns 404 and the ALB
# keeps this instance out of rotation.
set -euxo pipefail
mkdir -p /opt/app/frontend
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
