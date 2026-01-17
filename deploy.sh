#!/usr/bin/env bash
set -euo pipefail

# Deploy customized org-agenda-api container to Fly.io
# The container is built from dotfiles flake with org settings baked in

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Get the dotfiles input revision for tagging
DOTFILES_REV=$(nix flake metadata --json 2>/dev/null | jq -r '.locks.nodes.dotfiles.locked.rev // empty' || true)
if [[ -z "$DOTFILES_REV" ]]; then
  DOTFILES_REV=$(jq -r '.nodes.dotfiles.locked.rev' flake.lock)
fi
SHORT_REV="${DOTFILES_REV:0:7}"

echo "Dotfiles revision: $DOTFILES_REV"

# Build container from flake (pulls from dotfiles)
echo "Building container from flake..."
nix build .#container -o result-container

# Load into Docker
echo "Loading container into Docker..."
LOADED_IMAGE=$(docker load < result-container 2>&1 | grep -oP 'Loaded image: \K.*')
echo "Loaded: $LOADED_IMAGE"

# Tag and push to Fly.io registry
IMAGE_NAME="registry.fly.io/colonelpanic-org-agenda:$SHORT_REV"
echo "Tagging as $IMAGE_NAME..."
docker tag "$LOADED_IMAGE" "$IMAGE_NAME"

echo "Pushing to Fly.io registry..."
flyctl auth docker
docker push "$IMAGE_NAME"

# Decrypt secrets
echo "Decrypting secrets..."

IDENTITY=""
for key_type in ed25519 rsa; do
  if [[ -f "$HOME/.ssh/id_${key_type}" ]]; then
    IDENTITY="$HOME/.ssh/id_${key_type}"
    break
  fi
done

if [[ -z "$IDENTITY" ]]; then
  echo "Error: No SSH identity found" >&2
  exit 1
fi

GIT_SSH_KEY=$(age -d -i "$IDENTITY" secrets/git-ssh-key.age)
AUTH_PASSWORD=$(age -d -i "$IDENTITY" secrets/auth-password.age)

echo "Setting Fly.io secrets..."

SECRET_ARGS=(
  "GIT_SYNC_REPOSITORY=git@github.com:colonelpanic8/org.git"
  "GIT_SSH_PRIVATE_KEY=$GIT_SSH_KEY"
  "AUTH_USER=imalison"
  "AUTH_PASSWORD=$AUTH_PASSWORD"
  "GIT_USER_EMAIL=org-agenda-api@colonelpanic.io"
  "GIT_USER_NAME=org-agenda-api"
)

flyctl secrets set "${SECRET_ARGS[@]}" --stage

echo "Deploying $IMAGE_NAME..."
flyctl deploy --image "$IMAGE_NAME" "$@"

# Cleanup
rm -f result-container

echo "Done! Deployed $IMAGE_NAME"
