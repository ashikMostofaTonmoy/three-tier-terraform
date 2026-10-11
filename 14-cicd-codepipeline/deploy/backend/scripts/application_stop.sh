#!/bin/bash
# Runs from the PREVIOUS revision's bundle (CodeDeploy's rule). On an
# instance's very first deploy there's nothing running — that's fine.
export HOME=/root
pm2 delete backend >/dev/null 2>&1 || true
exit 0
