#!/bin/bash
# Host-side helper for the InfraPack console (macOS).
#
# The console runs in a container, so it cannot touch Docker Desktop, a macOS
# app. It writes a one-word action into ~/.infrapack/inbox/request instead;
# launchd notices and runs this script on the host to carry it out.
#
# Installed with:  infrapack agent install | uninstall | status
set -uo pipefail

A="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REQ="$A/inbox/request"
mkdir -p "$A/inbox"

log(){ printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$A/log"; }
say(){ printf '%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$1" "$2" > "$A/status"; }

[[ -f "$REQ" ]] || exit 0
action="$(head -c 64 "$REQ" | tr -d '[:space:]')"
rm -f "$REQ"

for p in /usr/local/bin /opt/homebrew/bin /Applications/Docker.app/Contents/Resources/bin; do
  [[ -x "$p/docker" ]] && DOCKER="$p/docker" && break
done
DOCKER="${DOCKER:-$(command -v docker || true)}"
[[ -n "$DOCKER" ]] || { log "docker CLI not found"; say error "docker CLI not found"; exit 1; }

case "$action" in
  restart-docker)
    log "restarting Docker Desktop"
    if "$DOCKER" desktop restart >>"$A/log" 2>&1; then
      log "restart finished"; say ok "Docker Desktop restarted"
    else
      log "restart failed"; say error "Docker Desktop restart failed"
    fi ;;
  *) log "ignoring unknown action: ${action:-<empty>}"; say error "unknown action" ;;
esac
