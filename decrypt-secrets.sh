#!/usr/bin/env bash
# Decrypt age secrets and export as environment variables
# This script is sourced by the nix shell hook

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info() {
  [[ -z "$SECRETS_QUIET" ]] && echo "$@"
}

# Load configuration if available
if [[ -f "$SCRIPT_DIR/config.env" ]]; then
  source "$SCRIPT_DIR/config.env"
fi

# Find an identity file (prefer config, then check common locations)
identity="${SSH_IDENTITY_FILE:-}"
if [[ -z "$identity" || ! -f "$identity" ]]; then
  for key_type in ed25519 rsa; do
    if [[ -f "$HOME/.ssh/id_${key_type}" ]]; then
      identity="$HOME/.ssh/id_${key_type}"
      break
    fi
  done
fi

# Also check for deploy key in secrets directory
if [[ -z "$identity" || ! -f "$identity" ]]; then
  if [[ -f "$SCRIPT_DIR/secrets/deploy-key" ]]; then
    identity="$SCRIPT_DIR/secrets/deploy-key"
  fi
fi

if [[ -z "$identity" || ! -f "$identity" ]]; then
  log_info "Secrets: no SSH identity found"
  return 0 2>/dev/null || exit 0
fi

decrypted=()
failed=()

for secretFile in "$SCRIPT_DIR"/secrets/*.age; do
  [[ ! -f "$secretFile" ]] && continue

  filename=$(basename "$secretFile")
  decryptedFileName="${filename%.age}"
  # Convert to env var: git-ssh-key -> GIT_SSH_KEY, auth-password -> AUTH_PASSWORD
  envVarName="$(echo "$decryptedFileName" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"

  content=$(age -d -i "$identity" "$secretFile" 2>/dev/null)
  if [[ $? -eq 0 ]]; then
    export "$envVarName"="$content"
    decrypted+=("$decryptedFileName")
  else
    failed+=("$decryptedFileName")
  fi
done

summary_parts=()
[[ ${#decrypted[@]} -gt 0 ]] && summary_parts+=("decrypted: ${#decrypted[@]}")
[[ ${#failed[@]} -gt 0 ]] && summary_parts+=("failed: ${failed[*]}")

if [[ ${#summary_parts[@]} -gt 0 ]]; then
  IFS='; '; summary="${summary_parts[*]}"; unset IFS
  log_info "Secrets: $summary"
fi
