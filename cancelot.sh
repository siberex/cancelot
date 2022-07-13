#!/usr/bin/env bash
# https://github.com/siberex/cancelot
#
# To download the latest version (if you trust running random bash scripts from the internets!):
# curl -L https://gist.github.com/siberex/bb0540b208019382d08732cc6dd59007/raw -o cancelot.sh && chmod +x cancelot.sh
#
# Provides automation for cancelling Cloud Builds
# Use as a first step to cancel previous builds currently in progress or queued for the same branch name and trigger id.
# Similar to: https://github.com/GoogleCloudPlatform/cloud-builders-community/tree/master/cancelot

# Usage stand-alone (gcloud CLI must be installed and authorised):
#    ./cancelot.sh --current_build_id $BUILD_ID --branch_name $BRANCH_NAME [--same_trigger_only] [--project "gcloud-project-id"] [--region ""]
#
# Could be configured with arguments or via ENV (or mixed).
# Arguments will take priority.
#
# Usage within Cloud Build step:
#    steps:
#    - name: 'gcr.io/google.com/cloudsdktool/google-cloud-cli:alpine'
#      entrypoint: bash
#      args:
#        - cancelot.sh --same_trigger_only
#      env:
#        - 'CURRENT_BUILD_ID=$BUILD_ID'
#        - 'PROJECT_ID=$PROJECT_ID'
#        - 'REGION=$LOCATION'

# Exit script when command fails
set -o errexit
# Return value of a pipeline is the value of the last (rightmost) command to exit with a non-zero status
set -o pipefail

# Note: GitHub App builds DOES NOT contain Source.RepoSource.Revision.BranchName field.
# The actual source for GitHub repo will be storageSource.bucket, check actual source with:
# $ gcloud builds describe $BUILD_ID --format=json

# We still could use substitutions.BRANCH_NAME
# https://cloud.google.com/build/docs/configuring-builds/substitute-variable-values

CMDNAME=${0##*/}
echoerr() { echo "$@" 1>&2; }

usage() {
    cat <<USAGE >&2
Usage:
    $CMDNAME --current_build_id \$BUILD_ID [--branch_name \$BRANCH_NAME] [--same_trigger_only]
    --current_build_id \$BUILD_ID  Current Build Id
    --branch_name \$BRANCH_NAME    Trigger branch (aka head branch)
                                    (optional, defaults to current build substitutions.BRANCH_NAME)
    --same_trigger_only           Only cancel builds with the same Trigger Id as current build’s trigger id
                                    (optional, defaults to false = cancel all matching branch)
USAGE
    exit 1
}

SAME_TRIGGER_ONLY=0

# Process arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
    --current_build_id)
        CURRENT_BUILD_ID="$2"
        if [[ $CURRENT_BUILD_ID == "" ]]; then break; fi
        shift 2
        ;;
    --branch_name)
        TARGET_BRANCH="$2"
        shift 2
        ;;
    --same_trigger_only)
        SAME_TRIGGER_ONLY=1
        shift 1
        ;;
    --project)
        PROJECT_ID="$2"
        shift 2
        ;;
    --region)
        REGION="$2"
        shift 2
        ;;
    --help)
        usage
        ;;
    *)
        echoerr "Unknown argument: $1"
        usage
        ;;
    esac
done

if [[ "$CURRENT_BUILD_ID" == "" ]]; then
    echo "Error: you need to provide Build Id"
    usage
fi

# In case Project Id were not provided via ENV or ARG, get it from the auth config.
# Could be useful to run cancelot locally or in CI environments other than Cloud Build.
GOOGLE_CLOUD_PROJECT=${PROJECT_ID:-$(gcloud config list --format 'get(core.project)')}

# Note: DO NOT guess Region from the Project. Region should be set explicitly (via ENV or ARG) or left empty.
# For example, we could get region for App Engine project like this:
#  gcloud app describe --project "$GOOGLE_CLOUD_PROJECT" --format 'get(locationId)'
# But Cloud Builds for AppEngine are multi-regional, so the correct value for region will be empty "" or "(unset)"
GOOGLE_CLOUD_REGION=${REGION:-"(unset)"}

echo "Getting Cloud Builds for ProjectId=$GOOGLE_CLOUD_PROJECT with region filter: $GOOGLE_CLOUD_REGION"

# Note BUILD_BRANCH and BUILD_TRIGGER_ID could be empty
QUERY_BUILD=$(gcloud builds describe "$CURRENT_BUILD_ID" --project="$GOOGLE_CLOUD_PROJECT" --region="$GOOGLE_CLOUD_REGION" --format="csv[no-heading](createTime, buildTriggerId, substitutions.BRANCH_NAME)")
IFS="," read -r BUILD_CREATE_TIME BUILD_TRIGGER_ID BUILD_BRANCH <<<"$QUERY_BUILD"

FILTERS="id!=$CURRENT_BUILD_ID AND createTime<$BUILD_CREATE_TIME"

if [[ -z $TARGET_BRANCH ]]; then
    TARGET_BRANCH="$BUILD_BRANCH"
fi
if [[ -n $TARGET_BRANCH ]]; then
FILTERS="$FILTERS AND substitutions.BRANCH_NAME=$TARGET_BRANCH"
fi

if [[ $SAME_TRIGGER_ONLY -eq 1 ]]; then
    # Get Trigger Id from current build
    FILTERS="$FILTERS AND buildTriggerId=$BUILD_TRIGGER_ID"
    echo "Filtering Trigger Id: $BUILD_TRIGGER_ID"
fi

echo "Filtering ongoing builds for branch '$TARGET_BRANCH' created before: $BUILD_CREATE_TIME"
# echo "$FILTERS"

# Get ongoing build ids to cancel (+status)
while IFS=$'\n' read -r line; do CANCEL_BUILDS+=("$line"); done < <(gcloud builds list --ongoing --filter="$FILTERS" --project="$GOOGLE_CLOUD_PROJECT" --region="$GOOGLE_CLOUD_REGION" --format="value(id, status)")

BUILDS_COUNT=${#CANCEL_BUILDS[@]}
echo "Found $BUILDS_COUNT builds to cancel"
if [[ $BUILDS_COUNT -eq 0 ]]; then
    exit 0
fi

# Cancel builds one by one to get output for each
# printf '%s\n' "${CANCEL_BUILDS[@]}"
echo "BUILD ID                                CURRENT STATUS"
for build in "${CANCEL_BUILDS[@]}"; do
    echo "$build"
    ID=$(echo "$build" | awk '{print $1;}')
    gcloud builds cancel "$ID" --project="$GOOGLE_CLOUD_PROJECT" --region="$GOOGLE_CLOUD_REGION" > /dev/null || true
done
