# org-agenda-api Template

Deploy your org-mode agenda as a secure REST API on [Fly.io](https://fly.io).

This template sets up [org-agenda-api](https://github.com/colonelpanic8/org-agenda-api) with:
- Encrypted secrets management (agenix)
- Automatic git sync of your org files
- HTTP Basic Auth protection
- Infrastructure as code (OpenTofu/Terraform)

## Prerequisites

### 1. Nix (required)

Install using the Determinate Systems installer (recommended):

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Or see [nixos.org/download](https://nixos.org/download.html) for other options.

### 2. direnv (recommended)

Automatically loads the development environment when you enter the directory.

```bash
# Install
nix profile install nixpkgs#direnv

# Add to your shell (~/.bashrc, ~/.zshrc, etc.)
eval "$(direnv hook bash)"  # or zsh, fish, etc.
```

See [direnv.net/docs/hook](https://direnv.net/docs/hook.html) for all shells.

### 3. Fly.io Account

1. Sign up at [fly.io/app/sign-up](https://fly.io/app/sign-up)
2. Credit card required (generous free tier available)
3. You'll authenticate later with `flyctl auth login`

### 4. Git Repository for Your Org Files

You need a git repository containing your `.org` files. This can be:
- A private GitHub/GitLab repo
- Any git server accessible via SSH

The deployed container will sync this repository to serve your agenda.

## Quick Start

### Option A: Interactive Setup (Recommended)

```bash
./setup.sh
```

This will:
- Check prerequisites and help install missing ones
- Generate a secure password (or let you choose one)
- Generate a dedicated SSH deploy key
- Create all configuration files
- Encrypt your secrets with agenix

### Option B: Manual Setup

1. Copy the example config:
   ```bash
   cp config.env.example config.env
   ```

2. Edit `config.env` with your values

3. Create your SSH key and secrets manually (see [Secrets Management](#secrets-management))

## Deployment

After running setup.sh (or manual setup):

```bash
# Enter the development shell (loads all tools)
nix develop
# Or if using direnv: direnv allow

# Authenticate with Fly.io
flyctl auth login

# Deploy infrastructure
tofu init
tofu apply

# Build container and set Fly.io secrets
./deploy.sh
```

Your API will be available at `https://YOUR-APP-NAME.fly.dev`

## Testing

```bash
# Enter dev shell first
nix develop

# Test the deployed API
curl -u YOUR_USER:YOUR_PASSWORD https://YOUR-APP-NAME.fly.dev/agenda

# Or use the justfile commands
just health   # Check if server is running
just agenda   # Get agenda (requires auth)
```

## Configuration

### config.env

Main configuration file (created by setup.sh or manually):

| Variable | Description |
|----------|-------------|
| `FLY_APP_NAME` | Your Fly.io app name (becomes `NAME.fly.dev`) |
| `FLY_REGION` | Deployment region (e.g., `ord`, `lax`, `ams`) |
| `AUTH_USER` | Username for HTTP Basic Auth |
| `GIT_SYNC_REPOSITORY` | SSH URL of your org files repo |
| `GIT_USER_EMAIL` | Email for git commits |
| `GIT_USER_NAME` | Name for git commits |
| `SSH_IDENTITY_FILE` | Path to SSH key for agenix |

### custom-config.el

Org-mode configuration loaded by Emacs. Edit this to customize:
- Which files to include in the agenda
- TODO keywords
- Custom agenda views
- Any other org-mode settings

See the file for examples and documentation.

## Secrets Management

Secrets are encrypted using [agenix](https://github.com/ryantm/agenix) and stored in the `secrets/` directory:

| File | Contents |
|------|----------|
| `secrets/auth-password.age` | API login password |
| `secrets/git-ssh-key.age` | SSH key for git sync |

### Editing Secrets

```bash
# Enter dev shell
nix develop

# Edit a secret (opens in $EDITOR)
agenix -e secrets/auth-password.age
```

### How It Works

1. Secrets are encrypted with your SSH key's public key (converted to age format)
2. When you enter `nix develop`, `decrypt-secrets.sh` decrypts them
3. Decrypted values are exported as environment variables
4. `deploy.sh` sends them to Fly.io's secret management

## Updating

### Update org-agenda-api version

```bash
nix flake update org-agenda-api
./deploy.sh
```

### Update your org files

The container automatically syncs your org repository. Changes appear within a few minutes.

## Troubleshooting

### "Permission denied" when syncing org repo

Make sure you've added the deploy key to your repository:
1. Get your public key: `cat secrets/deploy-key.pub` (or your SSH key's .pub file)
2. Add it as a deploy key in your repository settings

For GitHub: Repository Settings -> Deploy keys -> Add deploy key

### Secrets won't decrypt

Check that `SSH_IDENTITY_FILE` in config.env points to the correct key, or that your key exists at `~/.ssh/id_ed25519`.

### Container won't start

Check logs:
```bash
flyctl logs -a YOUR-APP-NAME
```

### Setup.sh fails on ssh-to-age

Make sure you're using an ed25519 SSH key. RSA keys may not work with all versions of ssh-to-age.

## API Endpoints

Once deployed, your API provides these endpoints:

| Endpoint | Description |
|----------|-------------|
| `GET /health` | Health check (no auth required) |
| `GET /agenda` | Today's agenda |
| `GET /get-all-todos` | All TODO items |
| `GET /get-todays-agenda` | Today's agenda items |
| `GET /agenda-files` | List of agenda files |
| `POST /create-todo` | Create a new TODO |

All endpoints except `/health` require HTTP Basic Auth.

## Advanced Usage

For a more advanced setup with tangled dotfiles integration, see:
[github.com/colonelpanic8/colonelpanic-org-agenda-api](https://github.com/colonelpanic8/colonelpanic-org-agenda-api)

## License

MIT
