#! /bin/sh
set -eu

# Replace this with your registry host. It must match the image names in
# double-tagging.clab.yaml and the auth entry in config.json.
REGISTRY="registry.example.com"
CHALLENGE="double-tagging"
CHALLENGE_IMAGE="$REGISTRY/challenges/$CHALLENGE/challenge:latest"

# Role images. Each folder holds <role>.containerfile and its entrypoint.
ROLES="switch router victim-client"

build_role() {
    role="$1"
    image="$REGISTRY/challenges/$CHALLENGE/$role:latest"
    echo "==> building $role"
    docker build -f "$role/$role.containerfile" -t "$image" "$role"
    echo "==> pushing $role"
    docker image push "$image"
}

# Push every role before building the challenge image: the base image's
# /app/prepull-images.sh pulls all images listed in the topology.
for role in $ROLES; do
    build_role "$role"
done

# BuildKit does not support custom runtimes like Sysbox. The base image's
# prepull script starts a nested dockerd during RUN, so use the legacy builder.
echo "==> building challenge image"
DOCKER_BUILDKIT=0 docker build -f challenge.containerfile -t "$CHALLENGE_IMAGE" .

echo "==> pushing challenge image"
docker image push "$CHALLENGE_IMAGE"
