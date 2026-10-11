#!/bin/bash
EXPECTED=$(cat /opt/app/frontend/version.txt)
for i in $(seq 1 15); do
  if [ "$(curl -fs http://127.0.0.1/version.txt)" = "$EXPECTED" ] && curl -fs http://127.0.0.1/ | grep -q '<div id="root">'; then
    echo "frontend $EXPECTED served"
    exit 0
  fi
  sleep 2
done
echo "frontend $EXPECTED not served" >&2
exit 1
