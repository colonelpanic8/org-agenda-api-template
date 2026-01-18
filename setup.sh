#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_step() {
    echo -e "${YELLOW}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "  $1"
}

wait_for_user() {
    echo ""
    read -p "Press Enter when ready to continue..."
    echo ""
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       org-agenda-api Deployment Template Setup               ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "This wizard will walk you through every step needed to deploy"
echo "your org-mode agenda as a REST API on Fly.io."
echo ""

# =============================================================================
print_header "Step 1: Check Prerequisites"
# =============================================================================

check_nix() {
    if ! command -v nix &> /dev/null; then
        print_error "Nix is not installed"
        echo ""
        echo "Nix is required to build and deploy. Install it with:"
        echo ""
        echo -e "  ${GREEN}curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install${NC}"
        echo ""
        echo "After installing, restart your shell and run this script again."
        return 1
    else
        print_success "Nix found: $(nix --version)"
        return 0
    fi
}

check_git() {
    if ! command -v git &> /dev/null; then
        print_error "git is not installed"
        return 1
    else
        print_success "git found"
        return 0
    fi
}

check_direnv() {
    if ! command -v direnv &> /dev/null; then
        echo -e "${YELLOW}! direnv not found (optional but recommended)${NC}"
        echo "  With direnv, the dev environment loads automatically when you cd here."
        echo "  Install: nix profile install nixpkgs#direnv"
        echo "  Setup:   https://direnv.net/docs/hook.html"
    else
        print_success "direnv found"
    fi
}

MISSING=0
check_nix || MISSING=1
check_git || MISSING=1
check_direnv

if [ $MISSING -eq 1 ]; then
    echo ""
    print_error "Please install missing prerequisites and run this script again."
    exit 1
fi

# =============================================================================
print_header "Step 2: Your Local SSH Key (for decrypting secrets)"
# =============================================================================

echo "Secrets in this project are encrypted with agenix, which uses your SSH key."
echo "You need an ed25519 SSH key on this machine to decrypt secrets."
echo ""

# Check for existing SSH keys
EXISTING_KEYS=()
for key_type in ed25519 rsa; do
    if [[ -f "$HOME/.ssh/id_${key_type}" ]]; then
        EXISTING_KEYS+=("$HOME/.ssh/id_${key_type}")
    fi
done

if [ ${#EXISTING_KEYS[@]} -eq 0 ]; then
    print_error "No SSH keys found in ~/.ssh/"
    echo ""
    echo "You need an SSH key. Generate one with:"
    echo ""
    echo -e "  ${GREEN}ssh-keygen -t ed25519 -C \"your-email@example.com\"${NC}"
    echo ""
    echo "Then run this script again."
    exit 1
fi

echo "Found existing SSH keys:"
for i in "${!EXISTING_KEYS[@]}"; do
    echo "  $((i+1))) ${EXISTING_KEYS[$i]}"
done
echo ""

if [ ${#EXISTING_KEYS[@]} -eq 1 ]; then
    LOCAL_SSH_KEY="${EXISTING_KEYS[0]}"
    echo "Using: $LOCAL_SSH_KEY"
else
    read -p "Which key to use for decrypting secrets? [1]: " KEY_CHOICE
    KEY_CHOICE=${KEY_CHOICE:-1}
    LOCAL_SSH_KEY="${EXISTING_KEYS[$((KEY_CHOICE-1))]}"
fi

# Verify it's ed25519 (preferred for age)
if [[ "$LOCAL_SSH_KEY" == *"ed25519"* ]]; then
    print_success "Using ed25519 key: $LOCAL_SSH_KEY"
else
    echo -e "${YELLOW}! Warning: RSA keys may have compatibility issues with agenix.${NC}"
    echo "  Consider generating an ed25519 key: ssh-keygen -t ed25519"
    read -p "Continue anyway? [y/N]: " CONTINUE
    if [[ "$CONTINUE" != "y" && "$CONTINUE" != "Y" ]]; then
        exit 1
    fi
fi

# =============================================================================
print_header "Step 3: Fly.io Account"
# =============================================================================

echo "Your API will be deployed to Fly.io (https://fly.io)."
echo ""
echo "Fly.io offers a generous free tier, but requires a credit card on file."
echo ""

if command -v flyctl &> /dev/null; then
    # flyctl available, check if logged in
    if flyctl auth whoami &> /dev/null; then
        FLY_USER=$(flyctl auth whoami 2>/dev/null)
        print_success "Already logged into Fly.io as: $FLY_USER"
    else
        print_step "You have flyctl but aren't logged in."
        echo ""
        echo "Let's log in now. This will open a browser."
        read -p "Press Enter to run 'flyctl auth login'..."
        flyctl auth login
        print_success "Logged into Fly.io"
    fi
else
    echo "flyctl is not installed globally (it will be available in nix develop)."
    echo ""
    echo "For now, make sure you have a Fly.io account:"
    echo "  1. Go to https://fly.io/app/sign-up"
    echo "  2. Create an account and add a payment method"
    echo ""
    read -p "Press Enter once you have a Fly.io account..."
fi

# =============================================================================
print_header "Step 4: Fly.io App Configuration"
# =============================================================================

echo "Choose a name for your Fly.io app. This will be part of your URL:"
echo "  https://YOUR-APP-NAME.fly.dev"
echo ""

while true; do
    read -p "App name (lowercase, hyphens ok): " FLY_APP_NAME
    if [[ "$FLY_APP_NAME" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] || [[ "$FLY_APP_NAME" =~ ^[a-z0-9]$ ]]; then
        break
    else
        print_error "Invalid name. Use lowercase letters, numbers, and hyphens only."
    fi
done

echo ""
echo "Choose a region for deployment. Pick one close to you for lower latency."
echo "Common regions: ord (Chicago), iad (Virginia), lax (Los Angeles),"
echo "                ams (Amsterdam), lhr (London), syd (Sydney)"
echo ""
read -p "Region [ord]: " FLY_REGION
FLY_REGION=${FLY_REGION:-ord}

print_success "App: $FLY_APP_NAME in region: $FLY_REGION"

# =============================================================================
print_header "Step 5: API Authentication"
# =============================================================================

echo "Your API will be protected with HTTP Basic Auth."
echo ""

read -p "Choose a username: " AUTH_USER

echo ""
echo "Password options:"
echo "  1) Generate a secure random password (recommended)"
echo "  2) Enter your own password"
read -p "Choice [1]: " PASSWORD_CHOICE
PASSWORD_CHOICE=${PASSWORD_CHOICE:-1}

if [ "$PASSWORD_CHOICE" = "1" ]; then
    AUTH_PASSWORD=$(openssl rand -base64 32 | tr -d '=/+' | head -c 24)
    echo ""
    echo -e "${GREEN}Generated password: ${BOLD}${AUTH_PASSWORD}${NC}"
    echo ""
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  SAVE THIS PASSWORD NOW! You won't see it again.           ║${NC}"
    echo -e "${YELLOW}║  It will be encrypted and stored in secrets/               ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
    wait_for_user
else
    read -sp "Enter password: " AUTH_PASSWORD
    echo ""
fi

print_success "Auth configured: $AUTH_USER / ********"

# =============================================================================
print_header "Step 6: Your Org Files Repository"
# =============================================================================

echo "The API needs access to a git repository containing your .org files."
echo "This should be a private repository accessible via SSH."
echo ""
echo -e "${YELLOW}Important:${NC} The contents of this repository will be synced to:"
echo -e "  ${BOLD}/data/org${NC}  (inside the deployed container)"
echo ""
echo "So if your repo has 'todos.org' at the root, it becomes '/data/org/todos.org'"
echo ""
echo "Examples:"
echo "  git@github.com:username/my-org-files.git"
echo "  git@gitlab.com:username/org-notes.git"
echo ""

read -p "Git repository SSH URL: " GIT_SYNC_REPOSITORY

echo ""
echo "Git identity for any commits made by the API (e.g., when creating TODOs):"
read -p "Git email [org-agenda-api@localhost]: " GIT_USER_EMAIL
GIT_USER_EMAIL=${GIT_USER_EMAIL:-org-agenda-api@localhost}
read -p "Git name [org-agenda-api]: " GIT_USER_NAME
GIT_USER_NAME=${GIT_USER_NAME:-org-agenda-api}

print_success "Git repo: $GIT_SYNC_REPOSITORY"

# =============================================================================
print_header "Step 7: Deploy Key (for Fly.io to access your repo)"
# =============================================================================

echo "The deployed container on Fly.io needs its own SSH key to clone your"
echo "org files repository. This is separate from your local SSH key."
echo ""
echo "We'll generate a dedicated deploy key and you'll add it to your repository."
echo ""

SSH_KEY_PATH="$SCRIPT_DIR/secrets/deploy-key"
mkdir -p "$SCRIPT_DIR/secrets"

if [ -f "$SSH_KEY_PATH" ]; then
    echo -e "${YELLOW}A deploy key already exists at: $SSH_KEY_PATH${NC}"
    read -p "Generate a new one? [y/N]: " REGENERATE
    if [[ "$REGENERATE" == "y" || "$REGENERATE" == "Y" ]]; then
        rm -f "$SSH_KEY_PATH" "$SSH_KEY_PATH.pub"
        ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "org-agenda-api-deploy-key"
        print_success "Generated new deploy key"
    else
        print_info "Using existing deploy key"
    fi
else
    print_step "Generating deploy key..."
    ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "org-agenda-api-deploy-key"
    print_success "Generated deploy key"
fi

echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  ACTION REQUIRED: Add this deploy key to your git repository  ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Public key to add:"
echo ""
echo -e "${GREEN}$(cat "${SSH_KEY_PATH}.pub")${NC}"
echo ""

# Try to parse the repo URL for helpful instructions
if [[ "$GIT_SYNC_REPOSITORY" == *"github.com"* ]]; then
    # Extract username/repo from git@github.com:user/repo.git
    REPO_PATH=$(echo "$GIT_SYNC_REPOSITORY" | sed 's/.*github.com[:\/]//' | sed 's/\.git$//')
    echo "For GitHub, go to:"
    echo -e "  ${BLUE}https://github.com/${REPO_PATH}/settings/keys${NC}"
    echo ""
    echo "Click 'Add deploy key', paste the key above, and save."
elif [[ "$GIT_SYNC_REPOSITORY" == *"gitlab.com"* ]]; then
    REPO_PATH=$(echo "$GIT_SYNC_REPOSITORY" | sed 's/.*gitlab.com[:\/]//' | sed 's/\.git$//')
    echo "For GitLab, go to:"
    echo -e "  ${BLUE}https://gitlab.com/${REPO_PATH}/-/settings/repository${NC}"
    echo ""
    echo "Expand 'Deploy keys', paste the key above, and save."
else
    echo "Add this public key as a deploy key in your git repository settings."
fi

echo ""
read -p "Press Enter once you've added the deploy key to your repository..."

# Verify the deploy key works
print_step "Testing deploy key..."
export GIT_SSH_COMMAND="ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=accept-new"

# Extract host from git URL
GIT_HOST=$(echo "$GIT_SYNC_REPOSITORY" | sed 's/.*@//' | sed 's/[:/].*//')

if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=accept-new -T "git@${GIT_HOST}" 2>&1 | grep -qi "success\|welcome\|authenticated"; then
    print_success "Deploy key authentication successful"
else
    echo -e "${YELLOW}! Could not verify deploy key (this might be ok)${NC}"
    echo "  The key may still work. We'll continue with setup."
    echo "  If deployment fails later, double-check the deploy key was added correctly."
fi

# =============================================================================
print_header "Step 8: Creating Encrypted Secrets"
# =============================================================================

echo "Now we'll encrypt your secrets using agenix."
echo "These can only be decrypted with your SSH key: $LOCAL_SSH_KEY"
echo ""

print_step "Converting SSH key to age format..."

# Get public key
if [ -f "${LOCAL_SSH_KEY}.pub" ]; then
    SSH_PUB_KEY=$(cat "${LOCAL_SSH_KEY}.pub")
else
    SSH_PUB_KEY=$(ssh-keygen -y -f "$LOCAL_SSH_KEY")
fi

# Convert to age key
if command -v ssh-to-age &> /dev/null; then
    AGE_KEY=$(echo "$SSH_PUB_KEY" | ssh-to-age)
else
    AGE_KEY=$(echo "$SSH_PUB_KEY" | nix shell nixpkgs#ssh-to-age -c ssh-to-age)
fi

print_success "Age public key: ${AGE_KEY:0:20}..."

# Create secrets.nix
print_step "Creating secrets.nix..."
cat > secrets.nix << EOF
# Agenix secrets configuration
# Generated by setup.sh on $(date)
#
# To re-encrypt secrets after adding new keys:
#   nix develop -c agenix -r
#
# To edit a secret:
#   nix develop -c agenix -e secrets/auth-password.age
{
  "secrets/git-ssh-key.age".publicKeys = [ "$AGE_KEY" ];
  "secrets/auth-password.age".publicKeys = [ "$AGE_KEY" ];
}
EOF
print_success "Created secrets.nix"

# Encrypt secrets
print_step "Encrypting deploy key..."
cat "$SSH_KEY_PATH" | nix shell nixpkgs#age -c age -r "$AGE_KEY" -o secrets/git-ssh-key.age
print_success "Created secrets/git-ssh-key.age"

print_step "Encrypting password..."
echo -n "$AUTH_PASSWORD" | nix shell nixpkgs#age -c age -r "$AGE_KEY" -o secrets/auth-password.age
print_success "Created secrets/auth-password.age"

# Test decryption
print_step "Verifying secrets can be decrypted..."
DECRYPTED_PASS=$(nix shell nixpkgs#age -c age -d -i "$LOCAL_SSH_KEY" secrets/auth-password.age 2>/dev/null) || true
if [ "$DECRYPTED_PASS" = "$AUTH_PASSWORD" ]; then
    print_success "Secret decryption verified"
else
    print_error "Could not verify secret decryption"
    echo "  This may indicate a problem with your SSH key or age."
    echo "  Continuing anyway, but deployment may fail."
fi

# =============================================================================
print_header "Step 9: Creating Configuration Files"
# =============================================================================

# config.env
print_step "Creating config.env..."
cat > config.env << EOF
# org-agenda-api configuration
# Generated by setup.sh on $(date)

# Fly.io settings
FLY_APP_NAME="$FLY_APP_NAME"
FLY_REGION="$FLY_REGION"

# API authentication
AUTH_USER="$AUTH_USER"

# Git repository for org files
GIT_SYNC_REPOSITORY="$GIT_SYNC_REPOSITORY"
GIT_USER_EMAIL="$GIT_USER_EMAIL"
GIT_USER_NAME="$GIT_USER_NAME"

# SSH key for decrypting secrets (your local key)
SSH_IDENTITY_FILE="$LOCAL_SSH_KEY"
EOF
print_success "Created config.env"

# terraform.tfvars
print_step "Creating terraform.tfvars..."
cat > terraform.tfvars << EOF
# Terraform variables
# Generated by setup.sh on $(date)
app_name = "$FLY_APP_NAME"
region   = "$FLY_REGION"
EOF
print_success "Created terraform.tfvars"

# Update fly.toml
print_step "Updating fly.toml..."
sed -i "s/^app = .*/app = \"$FLY_APP_NAME\"/" fly.toml
sed -i "s/^primary_region = .*/primary_region = \"$FLY_REGION\"/" fly.toml
print_success "Updated fly.toml"

# =============================================================================
print_header "Step 10: Org-mode Configuration"
# =============================================================================

echo "You should customize how org-mode processes your files by editing:"
echo -e "  ${BLUE}custom-config.el${NC}"
echo ""
echo -e "${YELLOW}Your org files will be at /data/org inside the container.${NC}"
echo ""
echo -e "${BOLD}Important settings to configure:${NC}"
echo ""
echo "  1. ${BOLD}org-agenda-files${NC} - which .org files to include in the agenda"
echo "     Default: all .org files recursively"
echo "     Example for specific files:"
echo -e "       ${GREEN}(setq org-agenda-files '(\"/data/org/todo.org\" \"/data/org/work.org\"))${NC}"
echo ""
echo "  2. ${BOLD}org-todo-keywords${NC} - your TODO states"
echo "     Example:"
echo -e "       ${GREEN}(setq org-todo-keywords"
echo -e "             '((sequence \"TODO\" \"IN-PROGRESS\" \"|\" \"DONE\" \"CANCELLED\")))${NC}"
echo ""
echo "  3. ${BOLD}Capture templates${NC} - for the /create-todo API endpoint"
echo "     Example:"
echo -e "       ${GREEN}(setq org-capture-templates"
echo -e "             '((\"t\" \"Todo\" entry (file \"/data/org/inbox.org\")"
echo -e "                \"* TODO %?\\n%U\")))${NC}"
echo ""
read -p "Would you like to edit custom-config.el now? [Y/n]: " EDIT_CONFIG
EDIT_CONFIG=${EDIT_CONFIG:-y}

if [[ "$EDIT_CONFIG" == "y" || "$EDIT_CONFIG" == "Y" ]]; then
    echo ""
    echo "Opening custom-config.el in ${EDITOR:-nano}..."
    echo "(Save and exit when done)"
    echo ""
    ${EDITOR:-nano} custom-config.el
    print_success "Updated custom-config.el"
else
    echo ""
    echo -e "${YELLOW}Remember to edit custom-config.el before deploying!${NC}"
    echo "The default includes ALL .org files, which may not be what you want."
fi

# =============================================================================
print_header "Setup Complete!"
# =============================================================================

echo -e "${GREEN}All configuration files have been created.${NC}"
echo ""
echo "Summary:"
echo "  App URL:     https://${FLY_APP_NAME}.fly.dev"
echo "  Username:    $AUTH_USER"
echo "  Password:    (encrypted in secrets/auth-password.age)"
echo "  Org repo:    $GIT_SYNC_REPOSITORY"
echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}Next Steps: Deploy to Fly.io${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "1. Enter the development shell (loads tools and decrypts secrets):"
echo ""
echo -e "   ${GREEN}nix develop${NC}"
echo ""
echo "2. Log into Fly.io (if not already):"
echo ""
echo -e "   ${GREEN}flyctl auth login${NC}"
echo ""
echo "3. Initialize and deploy infrastructure:"
echo ""
echo -e "   ${GREEN}tofu init${NC}"
echo -e "   ${GREEN}tofu apply${NC}"
echo ""
echo "4. Build and deploy your container:"
echo ""
echo -e "   ${GREEN}./deploy.sh${NC}"
echo ""
echo "5. Test your API:"
echo ""
echo -e "   ${GREEN}curl -u $AUTH_USER:'YOUR_PASSWORD' https://${FLY_APP_NAME}.fly.dev/health${NC}"
echo -e "   ${GREEN}just agenda${NC}  # (from within nix develop)"
echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
echo ""
