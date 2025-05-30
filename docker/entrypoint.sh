#!/bin/bash
set -e

# Cleanup function
cleanup() {
  echo "Received exit signal. Cleaning up..."
  kill -TERM "$NGINX_PID" "${DL_PID}" 2>/dev/null
  wait "$NGINX_PID" "${DL_PID}"
  exit 0
}

# Trap termination signals
trap cleanup SIGINT SIGTERM

# Create the output folder
mkdir -p /workspace/civitai-export 
chmod -R a+rX /workspace/civitai-export
# chown -R www-data:www-data /workspace/civitai-export

# Interpolate the config
envsubst < /etc/civitai/config.template.toml > /etc/civitai/config.toml

# Start nginx
nginx -g 'daemon off;' &
NGINX_PID=$!

# Split usernames by comma
DEFAULT_BASE_MODELS='SD 1.5,SDXL 1.0,Pony,Flux.1 D,Illustrious,NoobAI,Hunyuan Video,Wan Video,Other'

IFS=',' read -ra USERNAMES <<< "$CIVITAI_USERNAME"
IFS=',' read -ra BASE_MODELS <<< "${CIVITAI_BASE_MODELS:$DEFAULT_BASE_MODELS}"

# Sequentially process each user
for username in "${USERNAMES[@]}"; do
  echo "Starting download for user: $username"

  for base_model in "${BASE_MODELS[@]}"; do
    /usr/bin/civitai-downloader download --base-models "$base_model" -u "$username" -c 4 --model-info -y --config /etc/civitai/config.toml
  done

  /usr/bin/civitai-downloader images -u "$username" -c 4 --nsfw=true --metadata --config /etc/civitai/config.toml
  /usr/bin/civitai-downloader images -u "$username" -c 4 --nsfw=false --metadata --config /etc/civitai/config.toml

  # After downloads: fix ownership and permissions again
  chmod -R a+rX /workspace/civitai-export
  # chown -R www-data:www-data /workspace/civitai-export

  # Create a zip archive inside the export folder
  echo "Creating ZIP archive..."
  cd /workspace/civitai-export
  zip -r everything.zip .

  # Fix permissions for the ZIP too
  chmod a+r /workspace/civitai-export/everything.zip
  chown www-data:www-data /workspace/civitai-export/everything.zip

  echo "ZIP archive ready: /workspace/civitai-export/everything.zip"
done &

DL_PID=$!

# Wait for nginx and the download loop
wait "$NGINX_PID" "$DL_PID"
