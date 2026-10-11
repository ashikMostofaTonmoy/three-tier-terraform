#!/bin/bash
# The gate: if the new version isn't answering on this instance within 60s,
# exit non-zero — CodeDeploy marks the instance failed, keeps it OUT of the
# target group, and (with auto-rollback on) redeploys the last good revision.
EXPECTED=$(cat /opt/app/backend/VERSION)
for i in $(seq 1 30); do
  if curl -fs http://127.0.0.1:3000/health | grep -q "\"version\":\"$EXPECTED\""; then
    echo "backend $EXPECTED healthy"
    exit 0
  fi
  sleep 2
done
echo "backend $EXPECTED did not become healthy" >&2
exit 1
