#!/bin/bash
set -e

# --- Configuration ---
# Source the environment variables from the build workflow
source /etc/paka/env

# Path to the Python project's .env file
# IMPORTANT: Make sure this path matches your project location
PROJECT_ENV_FILE="/opt/paka-project/.env"
CLONE_PATH="/opt/paka-project"

echo "Running Paka first-boot setup..."

# 1. Clone the repository if it doesn't exist
if [ ! -d "$CLONE_PATH" ]; then
    echo "Cloning repository from $GITHUB_REPO_URL..."
    git clone "$GITHUB_REPO_URL" "$CLONE_PATH"
fi

# 2. Fetch the HMAC API Key
echo "Fetching HMAC key from API..."
API_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${PAKA_X_API_KEY}" \
  -H "x-name: ${PAKA_X_NAME}" \
  "${PAKA_SUPABASE_URL}/v1/raspberry-generate-hmac")

# Extract the key from the JSON response (assumes format is {"hmac": "VALUE"})
HMAC_KEY=$(echo "$API_RESPONSE" | grep -o '"hmac":"[^"]*' | grep -o '[^"]*$')

if [ -z "$HMAC_KEY" ]; then
    echo "ERROR: Failed to fetch HMAC key. API Response: $API_RESPONSE"
    exit 1
fi

echo "Successfully fetched HMAC key."

# 3. Create/Update the .env file
echo "Updating .env file at $PROJECT_ENV_FILE"
cat << EOF > "$PROJECT_ENV_FILE"
# Environment variables for the Paka Project
PAKA_SUPABASE_URL=${PAKA_SUPABASE_URL}
PAKA_SUPABASE_ANON_KEY=${PAKA_SUPABASE_ANON_KEY}
PAKA_DEVICE_NAME=${PAKA_DEVICE_NAME}
PAKA_HMAC_VALUE=${HMAC_KEY}
EOF

# Make sure the .env file has the correct permissions
chown ubuntu:ubuntu "$PROJECT_ENV_FILE"
chmod 600 "$PROJECT_ENV_FILE"

echo ".env file configured."

# 4. Disable this service so it doesn't run again
echo "Disabling first-boot service."
systemctl disable paka-first-boot.service

echo "First-boot setup complete."