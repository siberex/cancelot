# Cancelot

Provides automation for cancelling Google Cloud Builds.

Cancels previously queued builds in the same workflow on newly submitted build.

Aimed to replace [cancelot](https://github.com/GoogleCloudPlatform/cloud-builders-community/tree/master/cancelot) because of [issues with it](https://github.com/GoogleCloudPlatform/cloud-builders-community/issues/386#issuecomment-610702302).

Use as a first step to cancel previous builds which are currently in progress or queued for the same branch name.

Use `--same_trigger_only` to narrow down to builds triggered by the same trigger id.


# Usage (Cloud Builds) 

ℹ️ Tip: Use suitable regional registry to reduce cross-region traffic costs.

For example, `eu.gcr.io/google.com/cloudsdktool/google-cloud-cli:alpine`

```yaml
steps:
- name: 'gcr.io/google.com/cloudsdktool/google-cloud-cli:alpine'
  entrypoint: bash
  args:
    - cancelot.sh --current_build_id "${BUILD_ID}" --same_trigger_only
  env:
    - 'PROJECT_ID=$PROJECT_ID'
    - 'LOCATION=$LOCATION'
```

Both arguments and ENV variables are accepted and are interchangeable:

`--current_build_id $BUILD_ID` could be replaced with `CURRENT_BUILD_ID=$BUILD_ID` env.

`PROJECT_ID=$PROJECT_ID` could be replaced with `--project $PROJECT_ID` arg.

Arguments took precedence over ENV.


# Usage (Other CI)

Script could be used locally or with any CI environment with gcloud installed and authenticated (`gcloud auth login`).

```bash
./cancelot.sh --current_build_id $BUILD_ID --branch_name $BRANCH_NAME [--same_trigger_only] [--project "gcloud-project-id"] [--region "europe-west2"]
```

Locally with docker and passing auth config via volume mapping: 

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
