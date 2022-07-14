# Cancelot

Provides automation for cancelling Google Cloud Builds.

Cancels previously queued builds in the same workflow when new build is submitted.

For example, allows you to cancel builds running for the branch on new commits to this branch.

Aimed to replace [cancelot](https://github.com/GoogleCloudPlatform/cloud-builders-community/tree/master/cancelot) because of [issues with it](https://github.com/GoogleCloudPlatform/cloud-builders-community/issues/386#issuecomment-610702302).

Use as a first step to cancel previous builds currently in progress.

Use `--same_trigger_only` to narrow down to builds triggered by the same trigger id.


# Usage (Google Cloud Build) 

> ℹ️ Tip: Use suitable regional registry to reduce cross-region traffic costs.
>
> For example, `eu.gcr.io/google.com/cloudsdktool/google-cloud-cli:alpine` for `europe-*` regions.

Sample trigger config `.cloudbuild/pull-request-trigger.yml`:

```yaml
name: pull-request
description: Do some work on each PR
filename: .cloudbuild/pull-request-action.yaml
github:
  name: cancelot
  owner: siberex
  pullRequest:
    branch: ^main$
```

Sample action config, `.cloudbuild/pull-request-action.yaml`:

```yaml
steps:
- id: cancelot
  name: 'gcr.io/google.com/cloudsdktool/google-cloud-cli:alpine'
  entrypoint: bash
  args:
    # To download the latest version (if you trust running random bash scripts from the internets!):
    #- curl -L https://gist.github.com/siberex/bb0540b208019382d08732cc6dd59007/raw -o cancelot.sh && chmod +x cancelot.sh
    - cancelot.sh 
    -  --current_build_id "${BUILD_ID}"
    -  --branch_name "${BRANCH_NAME}"
    -  --same_trigger_only
  env:
    - 'PROJECT_ID=$PROJECT_ID'
    - 'LOCATION=$LOCATION'
- id: do-some-work
  waitFor: ['cancelot']
  name: alpine
  entrypoint: /bin/sh
  args:
    - -c
    - |
      sleep 5s
      echo JOB DONE!
```

Both CLI ARGS and ENV variables are accepted and are interchangeable:

`--current_build_id $BUILD_ID` could be replaced with `CURRENT_BUILD_ID=$BUILD_ID` env.

`PROJECT_ID=$PROJECT_ID` could be replaced with `--project $PROJECT_ID` arg.

Arguments took precedence over ENV.


# Usage (Other CI)

Script could be used locally or with any CI environment with gcloud installed and authenticated (`gcloud auth login`).

```bash
./cancelot.sh --current_build_id $BUILD_ID --branch_name $BRANCH_NAME [--same_trigger_only] [--project "gcloud-project-id"] [--region "europe-west2"]
```

You can download the latest version from gist, btw, without cloning the repo (if you trust running random bash scripts from the internets!):

```bash
curl -L https://gist.github.com/siberex/bb0540b208019382d08732cc6dd59007/raw -o cancelot.sh && chmod +x cancelot.sh
```

Run locally with docker and pass gcloud auth config from the host via volume mapping:

```bash
docker run -it --rm -e CLOUDSDK_CONFIG=/config/gcloud \
  -v "$HOME/.config/gcloud":/config/gcloud \
  -v "$PWD/cancelot.sh":/cancelot.sh \
  --entrypoint bash \
  gcr.io/google.com/cloudsdktool/google-cloud-cli:alpine \
  cancelot.sh --current_build_id abcdef12-3456-7890-a1b2-c3d4e5f6dead
```

[gcloud SDK official images](https://github.com/GoogleCloudPlatform/cloud-sdk-docker) – `gcr.io/google.com/cloudsdktool/google-cloud-cli:alpine`

[Cloud Builder gcloud image](https://github.com/GoogleCloudPlatform/cloud-builders/tree/master/gcloud) – `gcr.io/cloud-builders/gcloud-slim:latest`
