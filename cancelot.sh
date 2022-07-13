#!/usr/bin/env bash
# https://gist.github.com/siberex/bb0540b208019382d08732cc6dd59007

# Provides automation for cancelling Cloud Builds
# Use as a first step to cancel previous builds currently in progress or queued for the same branch name and trigger id.
# Similar to: https://github.com/GoogleCloudPlatform/cloud-builders-community/tree/master/cancelot

# Usage: cancelot.sh --current_build_id $BUILD_ID --branch_name $BRANCH_NAME --same_trigger_only
# Usage within Cloud Build step:
#    steps:
#    - name: 'gcr.io/cloud-builders/gcloud-slim:latest'
#      entrypoint: 'bash'
#      args: ['./cancelot.sh', '--current_build_id', '$BUILD_ID', '--same_trigger_only']

# Exit script when command fails
set -o errexit
# Return value of a pipeline is the value of the last (rightmost) command to exit with a non-zero status
set -o pipefail

# Note: GitHub App builds DOES NOT contain Source.RepoSource.Revision.BranchName field.
# The actual source for GitHub repo will be storageSource.bucket, check actual source with:
# $ gcloud builds describe $BUILD_ID --format=json

# We still could use substitutions.BRANCH_NAME
# https://cloud.google.com/cloud-build/docs/configuring-builds/substitute-variable-values

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

QUERY_BUILD=$(gcloud builds describe "$CURRENT_BUILD_ID" --format="value(buildTriggerId, createTime, substitutions.BRANCH_NAME)")
read -r BUILD_TRIGGER_ID BUILD_CREATE_TIME BUILD_BRANCH <<<"$QUERY_BUILD"

FILTERS="id!=$CURRENT_BUILD_ID AND createTime<$BUILD_CREATE_TIME"

if [[ "$TARGET_BRANCH" == "" ]]; then
    TARGET_BRANCH="$BUILD_BRANCH"
fi
FILTERS="$FILTERS AND substitutions.BRANCH_NAME=$TARGET_BRANCH"

if [[ $SAME_TRIGGER_ONLY -eq 1 ]]; then
    # Get Trigger Id from current build
    FILTERS="$FILTERS AND buildTriggerId=$BUILD_TRIGGER_ID"
    echo "Filtering Trigger Id: $BUILD_TRIGGER_ID"
fi

echo "Filtering ongoing builds for branch '$TARGET_BRANCH' created before: $BUILD_CREATE_TIME"
# echo "$FILTERS"

# Get ongoing build ids to cancel (+status)
while IFS=$'\n' read -r line; do CANCEL_BUILDS+=("$line"); done < <(gcloud builds list --ongoing --filter="$FILTERS" --format="value(id, status)")

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
    gcloud builds cancel "$ID" > /dev/null || true
done
