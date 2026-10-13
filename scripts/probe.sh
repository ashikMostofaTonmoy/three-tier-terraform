#!/bin/bash
# probe.sh — send requests to the app non-stop and log what answered.
#
# This is the "user traffic" behind every measured result in lessons 13-16:
# while you deploy, switch or break something, run this in another terminal
# and you can see — to the millisecond — whether any request failed and
# exactly when the version (and, in lesson 16, the color) changed.
#
#   bash scripts/probe.sh APP_URL [SECONDS] [INTERVAL] [FRONTEND_PATH]
#
#   APP_URL    e.g. http://three-tier-tf-16-alb-....elb.amazonaws.com
#              (get it with: terraform output -raw app_url)
#   SECONDS    how long to run (default 300). Ctrl-C stops early — the
#              summary is still printed.
#   INTERVAL   pause between requests in seconds (default 0 = back to back,
#              ~3-5 requests/second; lessons 13-15 used 1)
#   FRONTEND_PATH  optional: also request this path on the frontend each
#              round and log its status (lesson 13 used "/", lessons 14-15
#              "/version.txt") — so a frontend outage shows up too
#
# Each line:   12:34:56.789 UTC  200  version=3c5e059  color=green
# At the end:  total requests, count per HTTP status, and every moment the
#              version/color changed.
#
# Also sends traffic the CloudWatch dashboards can show — the load
# balancer's own health checks don't count as requests.
set -u
URL=${1:?usage: bash scripts/probe.sh APP_URL [SECONDS] [INTERVAL] [FRONTEND_PATH]}
SECONDS_TO_RUN=${2:-300}
INTERVAL=${3:-0}
FRONT_PATH=${4:-}
URL=${URL%/}

now() {  # UTC time with milliseconds (falls back to seconds where %N isn't supported, e.g. macOS)
  local t
  t=$(date -u +%H:%M:%S.%3N)
  case "$t" in *N*) date -u +%H:%M:%S ;; *) echo "$t" ;; esac
}

TOTAL=0
declare -A BY_STATUS=()
declare -A FRONT_STATUS=()
CHANGES=""
LAST=""

summary() {
  echo
  echo "=== probe summary: $TOTAL requests to $URL/health"
  for s in "${!BY_STATUS[@]}"; do
    case "$s" in 000) label="no answer (timeout/refused)" ;; *) label="HTTP $s" ;; esac
    echo "    ${BY_STATUS[$s]} × $label"
  done
  if [ -n "$FRONT_PATH" ]; then
    echo "=== frontend $URL$FRONT_PATH:"
    for s in "${!FRONT_STATUS[@]}"; do echo "    ${FRONT_STATUS[$s]} × $([ "$s" = 000 ] && echo 'no answer' || echo "HTTP $s")"; done
  fi
  echo "=== changes (first request that saw a new version/color):"
  printf '%b' "$CHANGES"
  exit 0
}
trap summary INT TERM

END=$(( $(date +%s) + SECONDS_TO_RUN ))
echo "probing $URL/health for ${SECONDS_TO_RUN}s — times are UTC"
while [ "$(date +%s)" -lt "$END" ]; do
  RESP=$(curl -s -m 3 -w ' %{http_code}' "$URL/health")
  CODE=${RESP##* }
  BODY=${RESP% *}
  VERSION=$(printf '%s' "$BODY" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
  COLOR=$(printf '%s' "$BODY" | sed -n 's/.*"color":"\([^"]*\)".*/\1/p')
  FRONT=""
  if [ -n "$FRONT_PATH" ]; then
    FCODE=$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$URL$FRONT_PATH")
    FRONT_STATUS[$FCODE]=$(( ${FRONT_STATUS[$FCODE]:-0} + 1 ))
    FRONT="  front=$FCODE"
  fi
  T=$(now)
  echo "$T UTC  $CODE  version=${VERSION:--}  color=${COLOR:--}$FRONT"
  TOTAL=$((TOTAL + 1))
  BY_STATUS[$CODE]=$(( ${BY_STATUS[$CODE]:-0} + 1 ))
  KEY="$VERSION/$COLOR"
  if [ -n "$VERSION" ] && [ "$KEY" != "$LAST" ]; then
    CHANGES="${CHANGES}    $T UTC  version=$VERSION  color=${COLOR:--}\n"
    LAST=$KEY
  fi
  [ "$INTERVAL" != 0 ] && sleep "$INTERVAL"
done
summary
