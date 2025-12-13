#!/usr/bin/env bash
# ---------------------------------------------------------------------
# Redis Local Build Script (Auto-detects working dir)
# ---------------------------------------------------------------------
set -euo pipefail

# 🔍 Determine the absolute path of this script and move there
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ENV_FILE="$SCRIPT_DIR/.env"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# ---------------------------------------------------------------------
# 1️⃣ Verify required files exist
# ---------------------------------------------------------------------
if [ ! -f "$COMPOSE_FILE" ]; then
  echo "❌ docker-compose.yml not found in $SCRIPT_DIR"
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ .env file not found in $SCRIPT_DIR"
  exit 1
fi

echo "🔧 Loading environment from .env..."

# ---------------------------------------------------------------------
# 2️⃣ Safe environment loader
# ---------------------------------------------------------------------
while IFS='=' read -r key value; do
  [[ -z "$key" || "$key" == \#* ]] && continue
  key=$(echo "$key" | xargs)
  value=$(echo "$value" | xargs)
  if [[ "$value" =~ ^\".*\"$ ]]; then
    value="${value:1:-1}"
  elif [[ "$value" =~ ^\'.*\'$ ]]; then
    value="${value:1:-1}"
  fi
  export "$key=$value"
done < "$ENV_FILE"

# ---------------------------------------------------------------------
# 3️⃣ Validate required vars
# ---------------------------------------------------------------------
REQUIRED_VARS=("REDIS_VERSION" "REDIS_PASSWORD" "REDIS_PORT" "REDIS_INTERNAL_PORT")
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "❌ Missing required environment variable: $var"
    exit 1
  fi
done

# ---------------------------------------------------------------------
# 4️⃣ Stop any old containers
# ---------------------------------------------------------------------
echo "🧹 Stopping and removing existing Redis container (if any)..."
docker compose -f "$COMPOSE_FILE" down --remove-orphans || true

# ---------------------------------------------------------------------
# 5️⃣ Build and start new container
# ---------------------------------------------------------------------
echo "🚀 Starting Redis using Docker Compose..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --build

# ---------------------------------------------------------------------
# 6️⃣ Check Redis readiness
# ---------------------------------------------------------------------
echo "⏳ Waiting for Redis to be ready..."
sleep 2

if docker exec -i "${REDIS_CONTAINER_NAME:-redis-local}" \
  redis-cli -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -q "PONG"; then
  echo "✅ Redis is running and authenticated successfully!"
else
  echo "⚠️ Redis did not respond to ping. Check logs below:"
  docker logs "${REDIS_CONTAINER_NAME:-redis-local}" | tail -n 20
  exit 1
fi

# ---------------------------------------------------------------------
# 7️⃣ Summary output
# ---------------------------------------------------------------------
cat <<EOF

📡 Connection Info:
  Host:   localhost
  Port:   ${REDIS_PORT}
  Auth:   ${REDIS_PASSWORD}

🧠 Manual connection:
  redis-cli -h localhost -p ${REDIS_PORT} -a ${REDIS_PASSWORD}

🪵 Logs:
  docker logs -f ${REDIS_CONTAINER_NAME:-redis-local}

🧹 Stop container:
  docker compose -f "$COMPOSE_FILE" down

✅ Done!
EOF