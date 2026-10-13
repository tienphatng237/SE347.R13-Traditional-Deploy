#!/usr/bin/env bash
set -euo pipefail
# Run on the server as a user allowed to use sudo. The application repository
# must already be cloned at /opt/application-web.
APP_DIR="${1:-/opt/application-web}"
WEB_ROOT="/var/www/roadmap-maker"
ENV_FILE="/etc/roadmap-maker/backend.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Create it from .env.production.example first." >&2
  exit 1
fi
if [[ ! -d "$APP_DIR/backend" || ! -d "$APP_DIR/frontend" ]]; then
  echo "Expected application source at $APP_DIR." >&2
  exit 1
fi
cd "$APP_DIR/backend"
npm ci --omit=dev
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
npx prisma generate
npx prisma migrate deploy
cd "$APP_DIR/frontend"
npm ci
VITE_API_BASE_URL=/api npm run build
sudo install -d -o deploy -g deploy "$WEB_ROOT"
sudo rsync -a --delete dist/ "$WEB_ROOT/"
sudo chown -R deploy:deploy "$WEB_ROOT"
sudo systemctl restart roadmap-maker-backend
sudo nginx -t
sudo systemctl reload nginx
echo "Deployment completed. Check: systemctl status roadmap-maker-backend"
