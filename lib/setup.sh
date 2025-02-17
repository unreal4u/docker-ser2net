set -e

require_main

OUTPUT_PREFIX="[setup]"

########################################################################
# Docker registry authentication
########################################################################

# ECR
if ! curl -s -S --fail --header "Authorization: Basic $(jq -r '.auths["'public.ecr.aws'"]["auth"]' ~/.docker/config.json)" public.ecr.aws/${PUBLIC_ECR_REGISTRY} > /dev/null
then
    debug "🔒 Logging in to AWS registry ..."
    aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws/${PUBLIC_ECR_REGISTRY}
    debug_complete "Login to AWS registry successful"
else
    debug_complete "Already logged in to AWS registry"
fi

# GitHub
if ! curl -s -S --fail --header "Authorization: Bearer $(jq -r '.auths["'ghcr.io'"]["auth"]' ~/.docker/config.json)" "https://ghcr.io/v2/" > /dev/null
then
    debug "🔒 Logging in to GitHub registry ..."
    if [ -z "${CR_PAT}" ]
    then
        debug_fail "Missing \$CR_PAT env key - See https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-to-the-container-registry"
        exit 1
    fi

    echo $CR_PAT | docker login ghcr.io -u jippi --password-stdin > /dev/null
    debug_complete "Login to GitHub registry successful"
else
    debug_complete "Already logged in to GitHub registry"
fi

########################################################################
# Build context
########################################################################

# Create buildx context
(
    docker buildx create --name $DOCKER_BUILDX_NAME --driver docker-container > /dev/null 2>&1 \
    && docker run --rm --privileged multiarch/qemu-user-static --reset -p yes \
    && debug_complete "buildx container builder created"
) || debug_complete "buildx container builder exists"

########################################################################
# Remote state
########################################################################

# find most recent docker tags from Docker Hub
debug_begin "Loading docker tags"
DOCKER_TAGS=$(curl -s "https://hub.docker.com/v2/repositories/${REPO_NAME_DOCKER_HUB}/tags/?page_size=100" | jq -r '.results[].name' | sort --numeric-sort)
debug_complete "Loading docker tags"

# find latest relases from cminyard/ser2net repository
debug_begin "Loading cminyard/ser2net releases"
github_releases=$(curl -s https://api.github.com/repos/cminyard/ser2net/tags?per_page=${NUMBER_OF_TAGS} | jq -r '.[].name' | sort --reverse --numeric-sort)
latest_release=$(echo "${github_releases}" | head -1)
debug_complete "Loading cminyard/ser2net releases"
