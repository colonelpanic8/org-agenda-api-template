#!/usr/bin/env bash
set -euo pipefail

# Deploy org-agenda-api container to Fly.io
# Prerequisites: Run this from within `nix develop` shell (secrets auto-decrypted)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load configuration
if [[ ! -f "$SCRIPT_DIR/config.env" ]]; then
  echo "Error: config.env not found. Run ./setup.sh first."
  exit 1
fi
source "$SCRIPT_DIR/config.env"

# Check that secrets are available (should be auto-decrypted by shell hook)
if [[ -z "${GIT_SSH_KEY:-}" ]]; then
  echo "Error: GIT_SSH_KEY not set. Make sure you're in the nix develop shell."
  echo "Run: nix develop"
  exit 1
fi

if [[ -z "${AUTH_PASSWORD:-}" ]]; then
  echo "Error: AUTH_PASSWORD not set. Make sure you're in the nix develop shell."
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

# Set Fly.io secrets (using auto-decrypted env vars)
echo "Setting Fly.io secrets..."
flyctl secrets set \
  "GIT_SYNC_REPOSITORY=${GIT_SYNC_REPOSITORY}" \
  "GIT_SSH_PRIVATE_KEY=${GIT_SSH_KEY}" \
  "AUTH_USER=${AUTH_USER}" \
  "AUTH_PASSWORD=${AUTH_PASSWORD}" \
  "GIT_USER_EMAIL=${GIT_USER_EMAIL}" \
  "GIT_USER_NAME=${GIT_USER_NAME}" \
  --stage

echo "Deploying $IMAGE_NAME..."
flyctl deploy --image "$IMAGE_NAME" "$@"

# Cleanup
rm -f result-container

echo "Done! Deployed $IMAGE_NAME"
