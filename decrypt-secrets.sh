#!/usr/bin/env bash
# Decrypt age secrets and export as environment variables

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info() {
  [[ -z "$SECRETS_QUIET" ]] && echo "$@"
}

# Find an identity file
identity=""
for key_type in ed25519 rsa; do
  if [[ -f "$HOME/.ssh/id_${key_type}" ]]; then
    identity="$HOME/.ssh/id_${key_type}"
    break
  fi
done

if [[ -z "$identity" ]]; then
  log_info "Secrets: no SSH identity found"
  return 0 2>/dev/null || exit 0
fi

decrypted=()
failed=()

for secretFile in "$SCRIPT_DIR"/secrets/*.age; do
  [[ ! -f "$secretFile" ]] && continue

  filename=$(basename "$secretFile")
  decryptedFileName="${filename%.age}"
  # Convert to TF_VAR format: git-ssh-key -> TF_VAR_git_ssh_private_key
  envVarName="TF_VAR_$(echo "$decryptedFileName" | tr '-' '_')"

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
