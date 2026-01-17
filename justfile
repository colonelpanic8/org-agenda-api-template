# org-agenda-api commands

# Load configuration from config.env
set dotenv-load := true
set dotenv-filename := "config.env"

# Computed values from config
base_url := "https://" + env_var('FLY_APP_NAME') + ".fly.dev"
user := env_var('AUTH_USER')

# Password from decrypted agenix secret (available after entering nix develop)
password := env_var_or_default('AUTH_PASSWORD', '')

# Get all todos
get-all-todos:
    @curl -s -u "{{user}}:{{password}}" "{{base_url}}/get-all-todos" | jq .

# Get today's agenda
get-todays-agenda:
    @curl -s -u "{{user}}:{{password}}" "{{base_url}}/get-todays-agenda" | jq .

# Get agenda (day view)
agenda:
    @curl -s -u "{{user}}:{{password}}" "{{base_url}}/agenda" | jq .

# Get agenda files
agenda-files:
    @curl -s -u "{{user}}:{{password}}" "{{base_url}}/agenda-files" | jq .

# Get todo states
todo-states:
    @curl -s -u "{{user}}:{{password}}" "{{base_url}}/todo-states" | jq .

# Health check
health:
    @curl -s "{{base_url}}/health" | jq .

# Create a todo
create-todo title:
    @curl -s -X POST -u "{{user}}:{{password}}" \
        -H "Content-Type: application/json" \
        -d '{"title": "{{title}}"}' \
        "{{base_url}}/create-todo" | jq .

# Test connection (same as health, but with verbose output)
test:
    @echo "Testing connection to {{base_url}}..."
    @curl -s "{{base_url}}/health" | jq .
