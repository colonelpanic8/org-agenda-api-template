#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       org-agenda-api Deployment Template Setup               ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

check_nix() {
    if ! command -v nix &> /dev/null; then
        echo -e "${RED}✗ Nix is not installed${NC}"
        echo ""
        echo -e "${YELLOW}To install Nix (recommended: Determinate Systems installer):${NC}"
        echo -e "  ${GREEN}curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install${NC}"
        echo ""
        echo "Or use the official installer:"
        echo "  https://nixos.org/download.html"
        echo ""
        return 1
    else
        echo -e "${GREEN}✓ Nix found${NC}"
        return 0
    fi
}

check_direnv() {
    if ! command -v direnv &> /dev/null; then
        echo -e "${YELLOW}! direnv not found (optional but recommended)${NC}"
        echo "  Install with: nix profile install nixpkgs#direnv"
        echo "  Then add to your shell: https://direnv.net/docs/hook.html"
        echo ""
    else
        echo -e "${GREEN}✓ direnv found${NC}"
    fi
}

check_git() {
    if ! command -v git &> /dev/null; then
        echo -e "${RED}✗ git is not installed${NC}"
        return 1
    else
        echo -e "${GREEN}✓ git found${NC}"
        return 0
    fi
}

MISSING=0
check_nix || MISSING=1
check_git || MISSING=1
check_direnv  # Optional, don't fail

if [ $MISSING -eq 1 ]; then
    echo -e "${RED}Please install missing prerequisites and try again.${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Let's configure your org-agenda-api deployment.${NC}"
echo ""

# === Fly.io Account ===
echo -e "${BLUE}=== Fly.io Account ===${NC}"
echo -e "${YELLOW}You'll need a Fly.io account to deploy. If you don't have one:${NC}"
echo "  1. Go to https://fly.io/app/sign-up"
echo "  2. Sign up (credit card required for deployment, but there's a free tier)"
echo "  3. After setup completes, run: flyctl auth login"
echo ""
read -p "Press Enter to continue (you can create your account later)..."
echo ""

# === Fly.io Configuration ===
echo -e "${BLUE}=== Fly.io Configuration ===${NC}"
read -p "Fly.io app name (e.g., my-org-agenda): " FLY_APP_NAME
read -p "Fly.io region [ord]: " FLY_REGION
FLY_REGION=${FLY_REGION:-ord}
echo ""

# === Authentication ===
echo -e "${BLUE}=== Authentication ===${NC}"
read -p "API username: " AUTH_USER

echo -e "${YELLOW}Password options:${NC}"
echo "  1) Generate a secure random password (recommended)"
echo "  2) Enter your own password"
read -p "Choice [1]: " PASSWORD_CHOICE
PASSWORD_CHOICE=${PASSWORD_CHOICE:-1}

if [ "$PASSWORD_CHOICE" = "1" ]; then
    AUTH_PASSWORD=$(openssl rand -base64 32 | tr -d '=/+' | head -c 24)
    echo -e "${GREEN}Generated password: ${AUTH_PASSWORD}${NC}"
    echo -e "${YELLOW}(Save this somewhere safe - you'll need it to access the API)${NC}"
else
    read -sp "Enter password: " AUTH_PASSWORD
    echo ""
fi
echo ""

# === Git Sync Configuration ===
echo -e "${BLUE}=== Git Repository (for your org files) ===${NC}"
read -p "Git repository SSH URL (e.g., git@github.com:you/org.git): " GIT_SYNC_REPOSITORY
read -p "Git commit email [org-agenda-api@localhost]: " GIT_USER_EMAIL
GIT_USER_EMAIL=${GIT_USER_EMAIL:-org-agenda-api@localhost}
read -p "Git commit name [org-agenda-api]: " GIT_USER_NAME
GIT_USER_NAME=${GIT_USER_NAME:-org-agenda-api}
echo ""

# === SSH Key Setup ===
echo -e "${BLUE}=== SSH Key for Secrets & Git Access ===${NC}"
echo -e "${YELLOW}You need an SSH key for two purposes:${NC}"
echo "  1) Encrypting secrets with agenix"
echo "  2) Accessing your private org repository from the deployed container"
echo ""
echo "Options:"
echo "  1) Generate a new dedicated deploy key (recommended)"
echo "  2) Use an existing SSH key"
read -p "Choice [1]: " SSH_CHOICE
SSH_CHOICE=${SSH_CHOICE:-1}

if [ "$SSH_CHOICE" = "1" ]; then
    SSH_KEY_PATH="$SCRIPT_DIR/secrets/deploy-key"
    mkdir -p "$SCRIPT_DIR/secrets"

    if [ -f "$SSH_KEY_PATH" ]; then
        echo -e "${YELLOW}Deploy key already exists at $SSH_KEY_PATH${NC}"
        read -p "Overwrite? [y/N]: " OVERWRITE
        if [ "$OVERWRITE" != "y" ] && [ "$OVERWRITE" != "Y" ]; then
            echo "Using existing key."
        else
            rm -f "$SSH_KEY_PATH" "$SSH_KEY_PATH.pub"
            ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "org-agenda-api-deploy"
            echo -e "${GREEN}✓ Generated new deploy key${NC}"
        fi
    else
        ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "org-agenda-api-deploy"
        echo -e "${GREEN}✓ Generated new deploy key${NC}"
    fi

    SSH_IDENTITY_FILE="$SSH_KEY_PATH"
    GIT_SSH_KEY_CONTENT=$(cat "$SSH_KEY_PATH")

    echo ""
    echo -e "${YELLOW}IMPORTANT: Add this public key as a deploy key to your org repository:${NC}"
    echo ""
    echo -e "${GREEN}$(cat "${SSH_KEY_PATH}.pub")${NC}"
    echo ""
    echo "Go to your repository settings and add this as a deploy key."
    echo "For GitHub: https://github.com/YOUR_USERNAME/YOUR_REPO/settings/keys"
    echo ""
    read -p "Press Enter once you've added the deploy key..."
else
    read -p "Path to existing SSH private key [$HOME/.ssh/id_ed25519]: " SSH_IDENTITY_FILE
    SSH_IDENTITY_FILE=${SSH_IDENTITY_FILE:-$HOME/.ssh/id_ed25519}

    if [ ! -f "$SSH_IDENTITY_FILE" ]; then
        echo -e "${RED}Error: $SSH_IDENTITY_FILE not found${NC}"
        exit 1
    fi
    GIT_SSH_KEY_CONTENT=$(cat "$SSH_IDENTITY_FILE")
fi
echo ""

# === Generate Configuration Files ===
echo -e "${YELLOW}Generating configuration files...${NC}"

# config.env
cat > config.env << EOF
# Generated by setup.sh on $(date)

FLY_APP_NAME="$FLY_APP_NAME"
FLY_REGION="$FLY_REGION"
AUTH_USER="$AUTH_USER"
GIT_SYNC_REPOSITORY="$GIT_SYNC_REPOSITORY"
GIT_USER_EMAIL="$GIT_USER_EMAIL"
GIT_USER_NAME="$GIT_USER_NAME"
SSH_IDENTITY_FILE="$SSH_IDENTITY_FILE"
EOF
echo -e "${GREEN}✓ config.env${NC}"

# terraform.tfvars
cat > terraform.tfvars << EOF
# Generated by setup.sh on $(date)
app_name = "$FLY_APP_NAME"
EOF
echo -e "${GREEN}✓ terraform.tfvars${NC}"

# fly.toml
sed -i "s/^app = .*/app = \"$FLY_APP_NAME\"/" fly.toml
sed -i "s/^primary_region = .*/primary_region = \"$FLY_REGION\"/" fly.toml
echo -e "${GREEN}✓ fly.toml updated${NC}"

# secrets.nix - need ssh-to-age from nix shell
echo -e "${YELLOW}Setting up agenix encryption...${NC}"

# Get public key
if [ -f "${SSH_IDENTITY_FILE}.pub" ]; then
    SSH_PUB_KEY=$(cat "${SSH_IDENTITY_FILE}.pub")
else
    SSH_PUB_KEY=$(ssh-keygen -y -f "$SSH_IDENTITY_FILE")
fi

# Try to convert to age key (might fail if ssh-to-age not available)
if command -v ssh-to-age &> /dev/null; then
    AGE_KEY=$(echo "$SSH_PUB_KEY" | ssh-to-age)
else
    # Use nix-shell to get ssh-to-age
    AGE_KEY=$(echo "$SSH_PUB_KEY" | nix shell nixpkgs#ssh-to-age -c ssh-to-age)
fi

cat > secrets.nix << EOF
# Generated by setup.sh on $(date)
{
  "secrets/git-ssh-key.age".publicKeys = [ "$AGE_KEY" ];
  "secrets/auth-password.age".publicKeys = [ "$AGE_KEY" ];
}
EOF
echo -e "${GREEN}✓ secrets.nix${NC}"

# Create encrypted secrets
echo -e "${YELLOW}Creating encrypted secrets...${NC}"
mkdir -p secrets

# Encrypt git SSH key
echo "$GIT_SSH_KEY_CONTENT" | nix shell nixpkgs#age -c age -r "$AGE_KEY" -o secrets/git-ssh-key.age
echo -e "${GREEN}✓ secrets/git-ssh-key.age${NC}"

# Encrypt password
echo "$AUTH_PASSWORD" | nix shell nixpkgs#age -c age -r "$AGE_KEY" -o secrets/auth-password.age
echo -e "${GREEN}✓ secrets/auth-password.age${NC}"

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    Setup Complete!                           ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Your configuration:${NC}"
echo "  App URL:    https://${FLY_APP_NAME}.fly.dev"
echo "  Username:   $AUTH_USER"
echo "  Password:   (encrypted in secrets/auth-password.age)"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "1. Enter the development shell:"
echo -e "   ${GREEN}nix develop${NC}"
echo ""
echo "2. Authenticate with Fly.io:"
echo -e "   ${GREEN}flyctl auth login${NC}"
echo ""
echo "3. Deploy the infrastructure:"
echo -e "   ${GREEN}tofu init${NC}"
echo -e "   ${GREEN}tofu apply${NC}"
echo ""
echo "4. Set secrets on Fly.io:"
echo -e "   ${GREEN}./deploy.sh${NC}"
echo ""
echo "5. Test the API:"
echo -e "   ${GREEN}curl -u $AUTH_USER:YOUR_PASSWORD https://${FLY_APP_NAME}.fly.dev/agenda${NC}"
echo ""
echo -e "${YELLOW}To customize org-mode:${NC}"
echo "  Edit custom-config.el to configure org-directory, org-agenda-files, etc."
echo ""
