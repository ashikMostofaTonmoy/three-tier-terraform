#!/bin/bash
# build-bundles.sh VERSION — run from the repo root.
# Turns the source tree into two CodeDeploy revisions under ./bundle/:
#   bundle/backend   app/ (code + production node_modules + migration) + appspec.yml + scripts/
#   bundle/frontend  site/ (Vite build + version.txt)                  + appspec.yml + scripts/
# The single source of truth for "what gets deployed" — CodeBuild calls it
# (buildspec.yml), GitHub Actions calls it (15-github-actions-asg), and
# you can run it on your laptop.
set -euo pipefail
VERSION=${1:?usage: build-bundles.sh VERSION}
HERE=14-cicd-codepipeline/deploy

rm -rf bundle
mkdir -p bundle/backend/app bundle/frontend/site

( cd frontend && npm ci && BUILD_ID="$VERSION" npm run build )
( cd backend && npm ci --omit=dev )

cp -r backend/src backend/node_modules backend/package.json backend/ecosystem.config.cjs bundle/backend/app/
cp database/migrations/*.sql bundle/backend/app/
echo "$VERSION" > bundle/backend/app/VERSION
cp -r "$HERE/backend/appspec.yml" "$HERE/backend/scripts" bundle/backend/

cp -r frontend/dist/. bundle/frontend/site/
echo "$VERSION" > bundle/frontend/site/version.txt
cp -r "$HERE/frontend/appspec.yml" "$HERE/frontend/scripts" bundle/frontend/

chmod +x bundle/*/scripts/*.sh
echo "bundles for $VERSION ready in ./bundle"
