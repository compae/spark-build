#!/usr/bin/env bash

# Builds a universe for this spark package
#
# Manifest config:
#   cli_version - version label to use for CLI package
#   spark_uri - where fetch spark distribution from (or SPARK_DIST_URI if provided)
#
# ENV vars:
#   DOCKER_IMAGE (optional) - "<image>:<version>", falls back to mesosphere/spark-dev:COMMIT)
#   COMMONS_TOOLS_DIR (optional) - path to dcos-commons/tools/, or empty to fetch latest release tgz
#   SPARK_DIST_URI (optional) - URI of spark distribution to use.
#   ghprbActualCommit / GIT_COMMIT (optional) - COMMIT value to use for DOCKER_IMAGE, if DOCKER_IMAGE isn't specified

set -e -x -o pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SPARK_BUILD_DIR="${DIR}/.."

# set CLI_VERSION, SPARK_DIST_URI, and DOCKER_IMAGE:
configure_env() {
    if [ -z "${SPARK_DIST_URI}" ]; then
        SPARK_DIST_URI=$(jq ".default_spark_dist.uri" "${SPARK_BUILD_DIR}/manifest.json")
        SPARK_DIST_URI="${SPARK_DIST_URI%\"}"
        SPARK_DIST_URI="${SPARK_DIST_URI#\"}"
        echo "Using Spark dist URI: $SPARK_DIST_URI"
    fi

    CLI_VERSION=$(jq ".cli_version" "${SPARK_BUILD_DIR}/manifest.json")
    CLI_VERSION="${CLI_VERSION%\"}"
    CLI_VERSION="${CLI_VERSION#\"}"
    echo "Using CLI Version: $CLI_VERSION"

    if [ -z "$DOCKER_IMAGE" ]; then
        # determine image label based on git commit:
        if [ -n "$ghprbActualCommit" ]; then
            # always overrides default GIT_COMMIT:
            GIT_COMMIT=$ghprbActualCommit
        fi
        if [ -z "$GIT_COMMIT" ]; then
            # Commit not explicitly provided by CI. Fetch directly from Git:
            GIT_COMMIT="$(git rev-parse HEAD)"
        fi
        if [ -z "$GIT_COMMIT" ]; then
            echo "Unable to determine git commit. Giving up."
            exit 1
        fi
        DOCKER_IMAGE="mesosphere/spark-dev:$GIT_COMMIT"
        echo "Using Docker image: $DOCKER_IMAGE"
    fi
}

fetch_commons_tools() {
    if [ -z "${COMMONS_TOOLS_DIR}" ]; then
        pushd ${DIR}
        rm -rf dcos-commons-tools/ && curl https://infinity-artifacts.s3.amazonaws.com/dcos-commons-tools.tgz | tar xz
        popd
        export COMMONS_TOOLS_DIR=${DIR}/dcos-commons-tools/
    fi
}

build_cli() {
    ls -all "${SPARK_BUILD_DIR}/cli"
    CLI_VERSION="${CLI_VERSION}" make --directory="${SPARK_BUILD_DIR}/cli" all
}

build_push_docker() {
    echo "###"
    echo "# Using docker image: $DOCKER_IMAGE"
    echo "###"

    pushd "${SPARK_BUILD_DIR}"
    make docker
    popd
}

upload_cli_and_stub_universe() {
    # Build/upload package using custom template parameters: TEMPLATE_X_Y_Z => {{x-y-z}}
    # ARTIFACT_DIR="https://${S3_BUCKET}.s3.amazonaws.com/${S3_PREFIX}" \
    # S3_DIR_PATH=${S3_PREFIX:-} \
    TEMPLATE_CLI_VERSION=${CLI_VERSION} \
    TEMPLATE_SPARK_DIST_URI=${SPARK_DIST_URI} \
    TEMPLATE_DOCKER_IMAGE=${DOCKER_IMAGE} \
        ${COMMONS_TOOLS_DIR}/ci_upload.py \
            spark \
            ${SPARK_BUILD_DIR}/package/ \
            ${SPARK_BUILD_DIR}/cli/dist/*.whl
}

configure_env
fetch_commons_tools
build_cli
build_push_docker
upload_cli_and_stub_universe
