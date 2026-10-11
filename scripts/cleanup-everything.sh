#!/bin/bash
# cleanup-everything.sh — delete EVERY AWS resource this course creates,
# found by name/tag (prefix "three-tier-terraform" / "three-tier-tf"), not by
# Terraform state. Use it after each class, or when state is lost/corrupted.
#
#   bash scripts/cleanup-everything.sh                 # dry run: list only
#   bash scripts/cleanup-everything.sh --yes           # actually delete
#   bash scripts/cleanup-everything.sh --yes --github-repo owner/repo
#                                                      # also delete the repo variables lessons 15/16 set
#   ... --include-github-oidc                          # also delete the account-wide GitHub OIDC provider
#
# The normal path is still `terraform destroy` per lesson (newest lesson
# first). This script is the safety net: it catches anything a destroy
# missed, a lesson someone forgot, or resources whose state is gone.
set -uo pipefail
# Git Bash on Windows rewrites arguments that look like paths
# ("/aws/codebuild/..." → "C:/Program Files/Git/aws/..."). Turn that off.
export MSYS_NO_PATHCONV=1

PROFILE=${AWS_PROFILE:-ostad}
REGION=${AWS_REGION:-ap-southeast-1}
YES=false; GH_REPO=""; GH_OIDC=false
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) YES=true ;;
    --github-repo) GH_REPO=$2; shift ;;
    --include-github-oidc) GH_OIDC=true ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

# aws.exe on Windows emits \r — strip it so values are usable in bash.
a() { aws --profile "$PROFILE" --region "$REGION" "$@" | tr -d '\r'; }
say() { printf '\n== %s\n' "$*"; }
act() {  # act "description" command...
  if $YES; then echo "  DELETE $1"; shift; "$@" >/dev/null || echo "  (failed — rerun the script)"; else echo "  would delete $1"; fi
}
P=three-tier-terraform

echo "Account $(a sts get-caller-identity --query Account --output text), region $REGION — $($YES && echo DELETING || echo 'DRY RUN (add --yes to delete)')"

say "Auto Scaling groups (first — otherwise they relaunch what we terminate)"
for g in $(a autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[?starts_with(AutoScalingGroupName,'$P')].AutoScalingGroupName" --output text); do
  act "ASG $g" a autoscaling delete-auto-scaling-group --auto-scaling-group-name "$g" --force-delete
done

say "CodePipeline / CodeBuild / CodeDeploy"
for p in $(a codepipeline list-pipelines --query "pipelines[?starts_with(name,'$P')].name" --output text); do act "pipeline $p" a codepipeline delete-pipeline --name "$p"; done
for p in $(a codebuild list-projects --query "projects[?starts_with(@,'$P')]" --output text); do act "codebuild $p" a codebuild delete-project --name "$p"; done
for d in $(a deploy list-applications --query "applications[?starts_with(@,'$P')]" --output text); do act "codedeploy app $d" a deploy delete-application --application-name "$d"; done

say "Load balancers"
LBS=$(a elbv2 describe-load-balancers --query "LoadBalancers[?starts_with(LoadBalancerName,'three-tier-tf')].LoadBalancerArn" --output text)
for lb in $LBS; do act "ALB ${lb##*/app/}" a elbv2 delete-load-balancer --load-balancer-arn "$lb"; done

say "RDS"
for db in $(a rds describe-db-instances --query "DBInstances[?starts_with(DBInstanceIdentifier,'$P')].DBInstanceIdentifier" --output text); do
  act "RDS $db" a rds delete-db-instance --db-instance-identifier "$db" --skip-final-snapshot --delete-automated-backups
done

say "Leftover EC2 instances (AMI builders, single-instance lessons)"
IDS=$(a ec2 describe-instances --filters "Name=tag:Name,Values=$P*" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'Reservations[].Instances[].InstanceId' --output text)
[ -n "$IDS" ] && act "instances $IDS" a ec2 terminate-instances --instance-ids $IDS

say "NAT gateways + Elastic IPs"
VPCS=$(a ec2 describe-vpcs --filters "Name=tag:Name,Values=$P*" --query 'Vpcs[].VpcId' --output text)
for v in $VPCS; do
  for n in $(a ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$v" "Name=state,Values=pending,available" --query 'NatGateways[].NatGatewayId' --output text); do
    act "NAT $n" a ec2 delete-nat-gateway --nat-gateway-id "$n"
  done
done

if $YES; then
  say "Waiting for ASGs, ALBs, instances, NAT gateways and RDS to finish deleting (several minutes)"
  for i in $(seq 1 60); do
    left=$(( $(a autoscaling describe-auto-scaling-groups --query "length(AutoScalingGroups[?starts_with(AutoScalingGroupName,'$P')])" --output text) \
           + $(a elbv2 describe-load-balancers --query "length(LoadBalancers[?starts_with(LoadBalancerName,'three-tier-tf')])" --output text) \
           + $(a ec2 describe-instances --filters "Name=tag:Name,Values=$P*" "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" --query 'length(Reservations[].Instances[])' --output text) \
           + $(a ec2 describe-nat-gateways --filter "Name=state,Values=pending,available,deleting" "Name=tag:Name,Values=$P*" --query 'length(NatGateways)' --output text) \
           + $(a rds describe-db-instances --query "length(DBInstances[?starts_with(DBInstanceIdentifier,'$P')])" --output text) ))
    echo "  $(date +%T) still deleting: $left"
    [ "$left" -eq 0 ] && break
    sleep 20
  done
fi

say "Elastic IPs"
for e in $(a ec2 describe-addresses --filters "Name=tag:Name,Values=$P*" --query 'Addresses[].AllocationId' --output text); do act "EIP $e" a ec2 release-address --allocation-id "$e"; done

say "Target groups, launch templates, DB subnet groups"
for t in $(a elbv2 describe-target-groups --query "TargetGroups[?starts_with(TargetGroupName,'three-tier-tf')].TargetGroupArn" --output text); do act "TG ${t##*targetgroup/}" a elbv2 delete-target-group --target-group-arn "$t"; done
for l in $(a ec2 describe-launch-templates --query "LaunchTemplates[?starts_with(LaunchTemplateName,'$P')].LaunchTemplateId" --output text); do act "launch template $l" a ec2 delete-launch-template --launch-template-id "$l"; done
for s in $(a rds describe-db-subnet-groups --query "DBSubnetGroups[?starts_with(DBSubnetGroupName,'$P')].DBSubnetGroupName" --output text); do act "DB subnet group $s" a rds delete-db-subnet-group --db-subnet-group-name "$s"; done

say "Security groups (rules revoked first — chained groups reference each other)"
SGS=$(a ec2 describe-security-groups --filters "Name=group-name,Values=$P*" --query 'SecurityGroups[].GroupId' --output text)
for sg in $SGS; do
  if $YES; then
    ING=$(a ec2 describe-security-groups --group-ids "$sg" --query 'SecurityGroups[0].IpPermissions' --output json)
    [ "$ING" != "[]" ] && a ec2 revoke-security-group-ingress --group-id "$sg" --ip-permissions "$ING" >/dev/null
  fi
done
for sg in $SGS; do act "SG $sg" a ec2 delete-security-group --group-id "$sg"; done

say "VPCs (subnets, route tables, internet gateways)"
for v in $VPCS; do
  for s in $(a ec2 describe-subnets --filters "Name=vpc-id,Values=$v" --query 'Subnets[].SubnetId' --output text); do act "subnet $s" a ec2 delete-subnet --subnet-id "$s"; done
  for r in $(a ec2 describe-route-tables --filters "Name=vpc-id,Values=$v" --query 'RouteTables[?!(Associations[?Main])].RouteTableId' --output text); do act "route table $r" a ec2 delete-route-table --route-table-id "$r"; done
  for g in $(a ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$v" --query 'InternetGateways[].InternetGatewayId' --output text); do
    act "detach IGW $g" a ec2 detach-internet-gateway --internet-gateway-id "$g" --vpc-id "$v"
    act "IGW $g" a ec2 delete-internet-gateway --internet-gateway-id "$g"
  done
  act "VPC $v" a ec2 delete-vpc --vpc-id "$v"
done

say "AMIs + their snapshots, key pairs"
for img in $(a ec2 describe-images --owners self --filters "Name=name,Values=$P*" --query 'Images[].ImageId' --output text); do
  SNAPS=$(a ec2 describe-images --image-ids "$img" --query 'Images[0].BlockDeviceMappings[].Ebs.SnapshotId' --output text)
  act "AMI $img" a ec2 deregister-image --image-id "$img"
  for s in $SNAPS; do act "snapshot $s" a ec2 delete-snapshot --snapshot-id "$s"; done
done
for k in $(a ec2 describe-key-pairs --query "KeyPairs[?starts_with(KeyName,'$P')].KeyName" --output text); do act "key pair $k" a ec2 delete-key-pair --key-name "$k"; done

say "Secrets Manager (no recovery window)"
for s in $(a secretsmanager list-secrets --query "SecretList[?starts_with(Name,'$P/')].ARN" --output text); do act "secret ${s##*:secret:}" a secretsmanager delete-secret --secret-id "$s" --force-delete-without-recovery; done

say "CloudWatch alarms + CodeBuild log groups"
AL=$(a cloudwatch describe-alarms --query "MetricAlarms[?starts_with(AlarmName,'$P') || starts_with(AlarmName,'TargetTracking-$P')].AlarmName" --output text)
[ -n "$AL" ] && act "alarms $AL" a cloudwatch delete-alarms --alarm-names $AL
for g in $(a logs describe-log-groups --log-group-name-prefix "/aws/codebuild/$P" --query 'logGroups[].logGroupName' --output text); do act "log group $g" a logs delete-log-group --log-group-name "$g"; done

say "IAM roles + instance profiles"
for r in $(a iam list-roles --query "Roles[?starts_with(RoleName,'$P')].RoleName" --output text); do
  if $YES; then
    for ip in $(a iam list-instance-profiles-for-role --role-name "$r" --query 'InstanceProfiles[].InstanceProfileName' --output text); do
      a iam remove-role-from-instance-profile --instance-profile-name "$ip" --role-name "$r" >/dev/null
      a iam delete-instance-profile --instance-profile-name "$ip" >/dev/null
    done
    for p in $(a iam list-role-policies --role-name "$r" --query 'PolicyNames' --output text); do a iam delete-role-policy --role-name "$r" --policy-name "$p" >/dev/null; done
    for p in $(a iam list-attached-role-policies --role-name "$r" --query 'AttachedPolicies[].PolicyArn' --output text); do a iam detach-role-policy --role-name "$r" --policy-arn "$p" >/dev/null; done
  fi
  act "role $r" a iam delete-role --role-name "$r"
done
for ip in $(a iam list-instance-profiles --query "InstanceProfiles[?starts_with(InstanceProfileName,'$P')].InstanceProfileName" --output text); do act "instance profile $ip" a iam delete-instance-profile --instance-profile-name "$ip"; done
if $GH_OIDC; then
  for o in $(a iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --output text | tr '\t' '\n' | grep token.actions.githubusercontent.com); do act "GitHub OIDC provider" a iam delete-open-id-connect-provider --open-id-connect-provider-arn "$o"; done
fi

say "GitHub connection"
for c in $(a codestar-connections list-connections --query "Connections[?starts_with(ConnectionName,'$P')].ConnectionArn" --output text); do act "connection ${c##*/}" a codestar-connections delete-connection --connection-arn "$c"; done

say "S3 buckets (every object version emptied first) — state bucket included"
for b in $(a s3api list-buckets --query "Buckets[?starts_with(Name,'$P')].Name" --output text); do
  if $YES; then
    while :; do
      DEL=$(a s3api list-object-versions --bucket "$b" --max-items 500 --output json \
        --query '{Objects: [Versions[].{Key:Key,VersionId:VersionId}, DeleteMarkers[].{Key:Key,VersionId:VersionId}][] }')
      echo "$DEL" | grep -q '"Key"' || break
      a s3api delete-objects --bucket "$b" --delete "$DEL" >/dev/null
    done
  fi
  act "bucket $b" a s3api delete-bucket --bucket "$b"
done

say "DynamoDB lock table"
for t in $(a dynamodb list-tables --query "TableNames[?starts_with(@,'$P')]" --output text); do act "table $t" a dynamodb delete-table --table-name "$t"; done

if [ -n "$GH_REPO" ]; then
  say "GitHub repo variables on $GH_REPO"
  # lesson 15's variables, then lesson 16's (BG_*) — only the ones that exist
  EXISTING=$(gh variable list --repo "$GH_REPO" --json name --jq '.[].name' 2>/dev/null)
  for v in AWS_REGION AWS_ROLE_ARN RELEASES_BUCKET BACKEND_ASG FRONTEND_ASG APP_URL            BG_AWS_REGION BG_AWS_ROLE_ARN BG_RELEASES_BUCKET BG_BLUE_ASG BG_GREEN_ASG            BG_BLUE_TG_ARN BG_GREEN_TG_ARN BG_RULE_ARN BG_FRONTEND_ASG BG_APP_URL; do
    echo "$EXISTING" | grep -qx "$v" && act "variable $v" gh variable delete "$v" --repo "$GH_REPO"
  done
fi

say "Done. $($YES && echo 'Run again without --yes — it should list nothing.' || echo 'Nothing was deleted. Re-run with --yes.')"
