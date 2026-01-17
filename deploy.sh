#!/usr/bin/env bash
set -euo pipefail

# Deploy org-agenda-api container to Fly.io

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load configuration
if [ -f "$SCRIPT_DIR/config.env" ]; then
    source "$SCRIPT_DIR/config.env"
else
    echo "Error: config.env not found. Run ./setup.sh first."
    exit 1
fi

# Get revision for tagging
FLAKE_REV=$(nix flake metadata --json 2>/dev/null | jq -r '.revision // empty' || true)
if [[ -z "$FLAKE_REV" ]]; then
  FLAKE_REV=$(git rev-parse --short HEAD 2>/dev/null || echo "latest")
fi
SHORT_REV="${FLAKE_REV:0:7}"

echo "Revision: $SHORT_REV"

# Build container from flake
echo "Building container from flake..."
nix build .#container -o result-container

# Load into Docker
echo "Loading container into Docker..."
LOADED_IMAGE=$(docker load < result-container 2>&1 | grep -oP 'Loaded image: \K.*')
echo "Loaded: $LOADED_IMAGE"

# Tag and push to Fly.io registry
IMAGE_NAME="registry.fly.io/${FLY_APP_NAME}:${SHORT_REV}"
echo "Tagging as $IMAGE_NAME..."
docker tag "$LOADED_IMAGE" "$IMAGE_NAME"

echo "Pushing to Fly.io registry..."
flyctl auth docker
docker push "$IMAGE_NAME"

# Decrypt secrets
echo "Decrypting secrets..."

IDENTITY="${SSH_IDENTITY_FILE:-}"
if [[ -z "$IDENTITY" ]]; then
    for key_type in ed25519 rsa; do
      if [[ -f "$HOME/.ssh/id_${key_type}" ]]; then
        IDENTITY="$HOME/.ssh/id_${key_type}"
        break
      fi
    done
fi

if [[ -z "$IDENTITY" || ! -f "$IDENTITY" ]]; then
  echo "Error: No SSH identity found. Set SSH_IDENTITY_FILE in config.env" >&2
  exit 1
fi

GIT_SSH_KEY=$(age -d -i "$IDENTITY" secrets/git-ssh-key.age)
AUTH_PASSWORD=$(age -d -i "$IDENTITY" secrets/auth-password.age)

echo "Setting Fly.io secrets..."

SECRET_ARGS=(
  "GIT_SYNC_REPOSITORY=${GIT_SYNC_REPOSITORY}"
  "GIT_SSH_PRIVATE_KEY=${GIT_SSH_KEY}"
  "AUTH_USER=${AUTH_USER}"
  "AUTH_PASSWORD=${AUTH_PASSWORD}"
  "GIT_USER_EMAIL=${GIT_USER_EMAIL}"
  "GIT_USER_NAME=${GIT_USER_NAME}"
)

flyctl secrets set "${SECRET_ARGS[@]}" --stage

echo "Deploying $IMAGE_NAME..."
flyctl deploy --image "$IMAGE_NAME" "$@"

# Cleanup
rm -f result-container

echo "Done! Deployed $IMAGE_NAME"
