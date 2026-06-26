#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/var/www/brenkschat}"
BRANCH="${BRANCH:-main}"
REMOTE="${REMOTE:-origin}"
SERVICE="${SERVICE:-brenkschat}"
RUN_TESTS="${RUN_TESTS:-0}"
SKIP_NGINX_RELOAD="${SKIP_NGINX_RELOAD:-0}"

log() {
  printf '\n==> %s\n' "$*"
}

fail() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Command not found: $1"
}

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  SUDO=()
else
  need_cmd sudo
  SUDO=(sudo)
fi

need_cmd git
need_cmd npm
need_cmd systemctl

log "BrenksChat production deploy"
printf 'App dir: %s\n' "$APP_DIR"
printf 'Remote: %s\n' "$REMOTE"
printf 'Branch: %s\n' "$BRANCH"
printf 'Service: %s\n' "$SERVICE"

[[ -d "$APP_DIR" ]] || fail "App directory does not exist: $APP_DIR"
cd "$APP_DIR"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
  fail "$APP_DIR is not a git repository"

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  git status --short --untracked-files=no
  fail "Working tree has local tracked changes. Commit, stash, or fix them before deploy."
fi

if [[ ! -f server/.env ]]; then
  fail "server/.env is missing on the server. Create it before deploy."
fi

log "Fetching latest code"
git fetch "$REMOTE" "$BRANCH"
git checkout "$BRANCH"
git pull --ff-only "$REMOTE" "$BRANCH"

log "Installing dependencies"
npm ci

if [[ "$RUN_TESTS" == "1" ]]; then
  log "Running server tests"
  npm run test -w server
fi

log "Building client and server"
npm run build

log "Restarting systemd service"
"${SUDO[@]}" systemctl restart "$SERVICE"

log "Checking service status"
"${SUDO[@]}" systemctl --no-pager --lines=20 status "$SERVICE"

if [[ "$SKIP_NGINX_RELOAD" != "1" ]]; then
  need_cmd nginx
  log "Testing nginx config"
  "${SUDO[@]}" nginx -t

  log "Reloading nginx"
  "${SUDO[@]}" systemctl reload nginx
fi

log "Deploy completed"
printf 'Site: https://brenkschat.ru\n'

