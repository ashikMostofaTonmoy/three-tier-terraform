#!/bin/bash
# cpu-load.sh — make every instance in an Auto Scaling group busy (or calm
# it down again), to watch scaling policies react. Used in lesson 13 §6.
#
#   bash scripts/cpu-load.sh ASG_NAME start [MINUTES] [PERCENT]
#   bash scripts/cpu-load.sh ASG_NAME stop
#
#   ASG_NAME  e.g. three-tier-terraform-13-backend
#             (list them: EC2 → Auto Scaling groups, or
#              aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[].AutoScalingGroupName')
#   MINUTES   how long the load lasts if you never run "stop" (default 15)
#   PERCENT   target CPU load per core (default 90)
#
# How it works: looks up the group's running (InService) instances, then
# runs `stress-ng` on all of them through SSM Run Command — no SSH, no
# keys. stress-ng is pre-installed in the lesson 12 image.
#
# Watch the effect: CloudWatch → Alarms (the scaling alarm goes
# "In alarm" after ~3 minutes), then EC2 → Auto Scaling groups → the group
# → Activity tab (the scale-out and its cause). See the command's own
# result: Systems Manager → Run Command → Command history.
set -euo pipefail
ASG=${1:?usage: bash scripts/cpu-load.sh ASG_NAME start|stop [MINUTES] [PERCENT]}
ACTION=${2:?usage: bash scripts/cpu-load.sh ASG_NAME start|stop [MINUTES] [PERCENT]}
MINUTES=${3:-15}
PERCENT=${4:-90}
PROFILE=${AWS_PROFILE:-ostad}
REGION=${AWS_REGION:-ap-southeast-1}

# aws.exe on Windows ends lines with \r — strip it so IDs are usable.
a() { aws --profile "$PROFILE" --region "$REGION" "$@" | tr -d '\r'; }

IDS=$(a autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' --output text)
[ -n "$IDS" ] && [ "$IDS" != "None" ] || { echo "no InService instances in $ASG (check the name)" >&2; exit 1; }
echo "$ASG: $(echo $IDS | wc -w) instance(s): $IDS"

case "$ACTION" in
  start) CMD="nohup stress-ng --cpu 0 --cpu-load $PERCENT --timeout $((MINUTES * 60))s >/dev/null 2>&1 & echo started" ;;
  stop)  CMD="pkill stress-ng && echo stopped || echo 'nothing was running'" ;;
  *) echo "ACTION must be start or stop" >&2; exit 2 ;;
esac

CID=$(a ssm send-command --document-name AWS-RunShellScript --instance-ids $IDS \
  --parameters "commands=[\"$CMD\"]" --comment "cpu-load $ACTION" \
  --query Command.CommandId --output text)
echo "SSM command $CID sent — waiting for each instance to answer..."
for id in $IDS; do
  until s=$(a ssm get-command-invocation --command-id "$CID" --instance-id "$id" --query Status --output text 2>/dev/null) \
        && [ "$s" != "Pending" ] && [ "$s" != "InProgress" ]; do sleep 2; done
  echo "  $id: $s — $(a ssm get-command-invocation --command-id "$CID" --instance-id "$id" --query StandardOutputContent --output text | tr -d '\n')"
done
[ "$ACTION" = start ] && echo "CPU load runs for up to $MINUTES min. Stop early: bash scripts/cpu-load.sh $ASG stop"
exit 0
