#!/bin/bash
# manual-deploy.sh VERSION — run from the repo root.
# Everything the pipeline does, by hand: build both bundles, zip them,
# upload to the pipeline's artifact bucket, and ask CodeDeploy to roll them
# out. Useful to see what CodePipeline automates, and as a fallback while a
# new AWS account's CodeBuild limit is still 0 (see the lesson README).
set -euo pipefail
VERSION=${1:?usage: manual-deploy.sh VERSION}
PROFILE=${AWS_PROFILE:-ostad}
REGION=${AWS_REGION:-ap-southeast-1}
APP=three-tier-terraform-14
ACCOUNT=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text | tr -d '\r')
BUCKET=three-tier-terraform-14-pipeline-$ACCOUNT

bash 14-cicd-codepipeline/deploy/build-bundles.sh "$VERSION"

for tier in backend frontend; do
  # Python's zipfile so the hook scripts keep their executable bit even when
  # this runs on Windows — CodeDeploy refuses to run a non-executable hook.
  python3 - "bundle/$tier" "bundle/$tier.zip" <<'PY'
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(src):
        for f in files:
            path = os.path.join(root, f)
            info = zipfile.ZipInfo.from_file(path, os.path.relpath(path, src).replace(os.sep, "/"))
            info.external_attr = (0o755 if f.endswith(".sh") else 0o644) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(path, "rb") as fh:
                z.writestr(info, fh.read())
PY
  KEY="manual/$tier-$VERSION.zip"
  aws s3 cp "bundle/$tier.zip" "s3://$BUCKET/$KEY" --profile "$PROFILE" --region "$REGION" --only-show-errors
  ID=$(aws deploy create-deployment --profile "$PROFILE" --region "$REGION" \
    --application-name "$APP" --deployment-group-name "$tier" \
    --s3-location "bucket=$BUCKET,key=$KEY,bundleType=zip" \
    --description "manual $VERSION" --query deploymentId --output text | tr -d '\r')
  echo "$tier: $ID"
done
