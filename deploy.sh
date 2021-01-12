#!/bin/bash -l
set -e

NO_COLOR='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'

# 1) Load our permissions in for aws-cli
export AWS_ACCESS_KEY_ID=$INPUT_AWS_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$INPUT_AWS_SECRET_KEY
export AWS_DEFAULT_REGION=$INPUT_AWS_REGION

# 2) Zip up the package
DIR_TO_ZIP="./$INPUT_DIRECTORY"
if [ ! -f "$DIR_TO_ZIP/appspec.yml" ]; then
    echo "::error::appspec.yml was not located at: $DIR_TO_ZIP"
    exit 1;
fi

ZIP_FILENAME=$GITHUB_RUN_ID-$GITHUB_SHA.zip
EXCLUDED_FILES_COMMAND=$(sed -En "s/ /-x/p")

zip -r --quiet "$ZIP_FILENAME" "$DIR_TO_ZIP" -x "$EXCLUDED_FILES_COMMAND" -x \*.git\*
if [ ! -f "$ZIP_FILENAME" ]; then
    echo "::error::$ZIP_FILENAME was not generated properly (zip generation failed)."
    exit 1;
fi

if [ "$(unzip -l "$ZIP_FILENAME" | grep -q appspec.yml)" = "0" ]; then
    echo "::error::$ZIP_FILENAME was not generated properly (missing appspec.yml)."
    exit 1;
fi

# 3) Upload the deployment to S3, drop old archive.
function getArchiveETag() {
    aws s3api head-object --bucket "$INPUT_S3_BUCKET" \
     --key "$INPUT_S3_FOLDER"/"$ZIP_FILENAME" \
     --query ETag --output text
}

aws s3 cp "$ZIP_FILENAME" s3://"$INPUT_S3_BUCKET"/"$INPUT_S3_FOLDER"/"$ZIP_FILENAME" > /dev/null 2>&1
ZIP_ETAG=$(getArchiveETag)

rm "$ZIP_FILENAME"

# 4) Start the CodeDeploy
function getActiveDeployments() {
    aws deploy list-deployments --application-name "$INPUT_CODEDEPLOY_NAME" \
        --deployment-group-name "$INPUT_CODEDEPLOY_GROUP" \
        --include-only-statuses "Queued" "InProgress" "Stopped" |  jq -r '.deployments';
}

function pollForActiveDeployments() {
    deadlockCounter=0;
    while [ "$(getActiveDeployments)" != "[]" ]; do
        echo -e "$ORANGE Deployment in progress. Sleeping 15 seconds. (Try $((++deadlockCounter)))";

        if [ "$deadlockCounter" -gt "$INPUT_MAX_POLLING_ITERATIONS" ]; then
            echo -e "$RED Max polling iterations reached (max_polling_iterations)."
            exit 1;
        fi
        sleep 15s;
    done;
}
pollForActiveDeployments

# 5) Poll / Complete
function deployRevision() {
    aws deploy create-deployment \
        --application-name "$INPUT_CODEDEPLOY_NAME" \
        --deployment-group-name "$INPUT_CODEDEPLOY_GROUP" \
        --description "$GITHUB_REF - $GITHUB_SHA" \
        --s3-location bucket="$INPUT_S3_BUCKET",bundleType=zip,eTag="$ZIP_ETAG",key="$INPUT_S3_FOLDER"/"$ZIP_FILENAME" > /dev/null 2>&1
}

echo -e "$BLUE Deploying to $NO_COLOR$INPUT_CODEDEPLOY_GROUP.";
deployRevision

sleep 10;
pollForActiveDeployments
echo -e "$GREEN Deployed to $NO_COLOR$INPUT_CODEDEPLOY_GROUP!";
exit 0;
