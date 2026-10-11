#!/bin/bash
set -euo pipefail
# CodeDeploy runs hooks without HOME set; PM2 keeps its state under $HOME/.pm2.
export HOME=/root
cd /opt/app/backend
pm2 start ecosystem.config.cjs
pm2 startup systemd -u root --hp /root >/dev/null
pm2 save
