#!/bin/bash
# Runs ONCE on the builder instance. Installs the runtime both tiers need —
# but deliberately NO application code: instances launched from this image
# fetch the current app build at boot (13-auto-scaling-groups), and in the CodePipeline/CodeDeploy
# topic CodeDeploy takes over that job. The image only changes when the runtime changes.
set -euxo pipefail
exec > /var/log/ami-build.log 2>&1

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx postgresql-client unzip curl ca-certificates gnupg \
  ruby-full wget python3 stress-ng

# AWS CLI v2 (Ubuntu's apt package is an old v1 build)
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install

# Node.js 20 + PM2
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
npm install -g pm2

# CodeDeploy agent — unused in 13-auto-scaling-groups, pre-installed so
# CodePipeline/CodeDeploy can deploy to any instance an ASG launches from this image.
cd /tmp
wget -q "https://aws-codedeploy-${aws_region}.s3.${aws_region}.amazonaws.com/latest/install"
chmod +x ./install
./install auto
systemctl enable codedeploy-agent

# Nginx is installed but off: only frontend instances turn it on (their
# launch template's user_data configures and starts it).
systemctl disable --now nginx

# Read PM2's version from its package.json — NOT `pm2 --version`. The
# first pm2 command of any kind spawns the PM2 daemon (and prints a
# full-screen ASCII banner), which would end up captured in this file and
# leave a /root/.pm2 runtime directory baked into the image (see the
# lesson README, "Common pitfall: build steps with side effects").
cat > /etc/three-tier-ami-release <<EOF
image=three-tier-terraform-app-runtime
version=${ami_version}
node=$(node --version)
pm2=$(node -p "require('/usr/lib/node_modules/pm2/package.json').version")
aws=$(aws --version 2>&1 | cut -d' ' -f1)
nginx=$(nginx -v 2>&1 | cut -d/ -f2)
codedeploy=$(dpkg -s codedeploy-agent | grep '^Version' | cut -d' ' -f2)
built=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

apt-get clean
rm -rf /tmp/aws /tmp/awscliv2.zip /tmp/install

# The signal Terraform waits for: a stopped instance means the build
# finished (set -e above means any failed step leaves it running instead).
shutdown -h now
