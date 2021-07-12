#!/bin/bash
set -e

RESET_TEXT='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'

# 0) Validation
if [ -z "$INPUT_CODEDEPLOY_NAME" ] && [ -z "$INPUT_DRY_RUN" ]; then
    echo "::error::codedeploy_name is required and must not be empty."
    exit 1;
fi

if [ -z "$INPUT_CODEDEPLOY_GROUP" ] && [ -z "$INPUT_DRY_RUN" ]; then
    echo "::error::codedeploy_group is required and must not be empty."
    exit 1;
fi

if [ -z "$INPUT_AWS_ACCESS_KEY" ] && [ -z "$INPUT_DRY_RUN" ]; then
    echo "::error::aws_access_key is required and must not be empty."
    exit 1;
fi

if [ -z "$INPUT_AWS_SECRET_KEY" ] && [ -z "$INPUT_DRY_RUN" ]; then
    echo "::error::aws_secret_key is required and must not be empty."
    exit 1;
fi

if [ -z "$INPUT_S3_BUCKET" ] && [ -z "$INPUT_DRY_RUN" ]; then
    echo "::error::s3_bucket is required and must not be empty."
    exit 1;
fi

echo "::debug::Input variables correctly validated."

# 1) Load our permissions in for aws-cli
export AWS_ACCESS_KEY_ID=$INPUT_AWS_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$INPUT_AWS_SECRET_KEY
export AWS_DEFAULT_REGION=$INPUT_AWS_REGION

# 2) Zip up the package, if no archive given
if [ -z "$INPUT_ARCHIVE" ]; then

    DIR_TO_ZIP="./$INPUT_DIRECTORY"
    if [ ! -f "$DIR_TO_ZIP/appspec.yml" ]; then
        echo "::error::appspec.yml was not located at: $DIR_TO_ZIP"
        exit 1;
    fi

    echo "::debug::Zip directory located (with appspec.yml)."

    ZIP_FILENAME=$INPUT_CODEDEPLOY_NAME-$INPUT_CODEDEPLOY_GROUP.zip

    # This creates a temp file to explode space delimited excluded files
    # into newline delimited exclusions passed to "-x" on the zip command.
    EXCLUSION_FILE=$(mktemp /tmp/zip-excluded.XXXXXX)
    echo "$INPUT_EXCLUDED_FILES" | tr ' ' '\n' > "$EXCLUSION_FILE"

    echo "::debug::Exclusion file created for files to ignore in Zip Generation."

    if [ -n "$DIR_TO_ZIP" ]; then
        cd "$DIR_TO_ZIP";
    fi

    zip -r --quiet "$ZIP_FILENAME" . -x "@$EXCLUSION_FILE"
    if [ ! -f "$ZIP_FILENAME" ]; then
        echo "::error::$ZIP_FILENAME was not generated properly (zip generation failed)."
        exit 1;
    fi

    echo "::debug::Zip Archive created."
else
    echo "::debug::$INPUT_ARCHIVE being using as zip filename. Skipping generation of ZIP."
    ZIP_FILENAME="$INPUT_ARCHIVE"
fi


if [ "$(unzip -l "$ZIP_FILENAME" | grep -q appspec.yml)" = "0" ]; then
    echo "::error::$ZIP_FILENAME was not generated properly (missing appspec.yml)."
    exit 1;
fi

echo "::debug::Zip Archived validated."
echo "::set-output name=zip_filename::$ZIP_FILENAME"

# 3) Upload the deployment to S3, drop old archive.
function getArchiveETag() {
    aws s3api head-object \
     --bucket "$INPUT_S3_BUCKET" \
     --key "$INPUT_S3_FOLDER"/"$ZIP_FILENAME" \
     --query ETag --output text
}

if "$INPUT_DRY_RUN"; then
    echo "::debug::Dry Run detected. Exiting."
    exit 0;
fi

aws s3 cp "$ZIP_FILENAME" s3://"$INPUT_S3_BUCKET"/"$INPUT_S3_FOLDER"/"$ZIP_FILENAME"

echo "::debug::Zip uploaded to S3."

ZIP_ETAG=$(getArchiveETag)

echo "::debug::Obtained ETag of uploaded S3 Zip Archive."
echo "::set-output name=etag::$ZIP_ETAG"

rm "$ZIP_FILENAME"

echo "::debug::Removed old local ZIP Archive."

# 4) Start the CodeDeploy
function getActiveDeployments() {
    aws deploy list-deployments \
        --application-name "$INPUT_CODEDEPLOY_NAME" \
        --deployment-group-name "$INPUT_CODEDEPLOY_GROUP" \
        --include-only-statuses "Queued" "InProgress" |  jq -r '.deployments';
}

function getSpecificDeployment() {
    aws deploy get-deployment \
        --deployment-id "$1";
}

function pollForSpecificDeployment() {
    deadlockCounter=0;

    while true; do
        RESPONSE=$(getSpecificDeployment "$1")
        FAILED_COUNT=$(echo "$RESPONSE" | jq -r '.deploymentInfo.deploymentOverview.Failed')
        IN_PROGRESS_COUNT=$(echo "$RESPONSE" | jq -r '.deploymentInfo.deploymentOverview.InProgress')
        SKIPPED_COUNT=$(echo "$RESPONSE" | jq -r '.deploymentInfo.deploymentOverview.Skipped')
        SUCCESS_COUNT=$(echo "$RESPONSE" | jq -r '.deploymentInfo.deploymentOverview.Succeeded')
        PENDING_COUNT=$(echo "$RESPONSE" | jq -r '.deploymentInfo.deploymentOverview.Pending')
        STATUS=$(echo "$RESPONSE" | jq -r '.deploymentInfo.status')

        echo -e "${ORANGE}Deployment in progress. Sleeping 15 seconds. (Try $((++deadlockCounter)))";
        echo -e "Instance Overview: ${RED}Failed ($FAILED_COUNT), ${BLUE}In-Progress ($IN_PROGRESS_COUNT), ${RESET_TEXT}Skipped ($SKIPPED_COUNT), ${BLUE}Pending ($PENDING_COUNT), ${GREEN}Succeeded ($SUCCESS_COUNT)"
        echo -e "Deployment Status: $STATUS"

        if [ "$FAILED_COUNT" -gt 0 ]; then
            echo -e "${RED}Failed instance detected (Failed count over zero)."
            exit 1;
        fi

        if [ "$STATUS" = "Failed" ]; then
            echo -e "${RED}Failed deployment detected (Failed status)."
            exit 1;
        fi

        if [ "$STATUS" = "Succeeded" ]; then
            break;
        fi

        if [ "$deadlockCounter" -gt "$INPUT_MAX_POLLING_ITERATIONS" ]; then
            echo -e "${RED}Max polling iterations reached (max_polling_iterations)."
            exit 1;
        fi
        sleep 15s;
    done;
}

function pollForActiveDeployments() {
    deadlockCounter=0;
    while [ "$(getActiveDeployments)" != "[]" ]; do
        echo -e "${ORANGE}Deployment in progress. Sleeping 15 seconds. (Try $((++deadlockCounter)))";

        if [ "$deadlockCounter" -gt "$INPUT_MAX_POLLING_ITERATIONS" ]; then
            echo -e "${RED}Max polling iterations reached (max_polling_iterations)."
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
        --s3-location bucket="$INPUT_S3_BUCKET",bundleType=zip,eTag="$ZIP_ETAG",key="$INPUT_S3_FOLDER"/"$ZIP_FILENAME" | jq -r '.deploymentId'
}

function registerRevision() {
    aws deploy register-application-revision \
        --application-name "$INPUT_CODEDEPLOY_NAME" \
        --description "$GITHUB_REF - $GITHUB_SHA" \
        --s3-location bucket="$INPUT_S3_BUCKET",bundleType=zip,eTag="$ZIP_ETAG",key="$INPUT_S3_FOLDER"/"$ZIP_FILENAME" > /dev/null 2>&1
}

if $INPUT_CODEDEPLOY_REGISTER_ONLY; then
    echo -e "${BLUE}Registering deployment to ${RESET_TEXT}$INPUT_CODEDEPLOY_GROUP.";
    registerRevision
    echo -e "${BLUE}Registered deployment to ${RESET_TEXT}$INPUT_CODEDEPLOY_GROUP!";
else
    echo -e "${BLUE}Registering deployment to ${RESET_TEXT}$INPUT_CODEDEPLOY_GROUP.";
    registerRevision
    echo -e "${BLUE}Registered deployment to ${RESET_TEXT}$INPUT_CODEDEPLOY_GROUP!";
    echo -e "${BLUE}Deploying to ${RESET_TEXT}$INPUT_CODEDEPLOY_GROUP.";
    DEPLOYMENT_ID=$(deployRevision)

    sleep 10;
    pollForSpecificDeployment "$DEPLOYMENT_ID"
    echo -e "${GREEN}Deployed to ${RESET_TEXT}$INPUT_CODEDEPLOY_GROUP!";
fi
    echo -e "${GREEN}Latest eTag: ${RESET_TEXT}$ZIP_ETAG"
exit 0;
