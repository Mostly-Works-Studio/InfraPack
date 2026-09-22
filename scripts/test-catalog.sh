#!/usr/bin/env bash
# Boot-test catalog entries: install, wait until every service is running
# (and healthy if it has a healthcheck), then uninstall with --purge.
#
#   scripts/test-catalog.sh              # every entry
#   scripts/test-catalog.sh redis nats   # just these
#   TIMEOUT=240 scripts/test-catalog.sh  # per-entry wait, seconds (default 180)
#   PRUNE=1 scripts/test-catalog.sh      # drop each entry's images afterwards (CI disk)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
IP="$HERE/bin/infrapack"
TIMEOUT="${TIMEOUT:-180}"
PROJECT=infrapack

entries=("$@")
if [[ ${#entries[@]} -eq 0 ]]; then
  for d in "$HERE"/catalog/*/; do entries+=("$(basename "$d")"); done
fi

services_of() {                    # same awk the CLI uses
  awk '/^services:[ \t]*$/{s=1;next} /^[^ \t#]/{s=0} s && /^  [A-Za-z0-9_.-]+:[ \t]*$/{sub(/^  /,"");sub(/:.*/,"");print}' "$1"
}

pass=() fail=()
for name in "${entries[@]}"; do
  printf '\n\033[1m=== %s ===\033[0m\n' "$name"
  start=$(date +%s)
  if ! "$IP" install "$name" >"/tmp/infrapack-test-$name.log" 2>&1; then
    echo "  install failed — see /tmp/infrapack-test-$name.log"; tail -20 "/tmp/infrapack-test-$name.log"
    fail+=("$name (install)"); "$IP" uninstall "$name" --purge >/dev/null 2>&1; continue
  fi
  ok=0
  while (( $(date +%s) - start < TIMEOUT )); do
    all=1
    for svc in $(services_of "$HOME/.infrapack/stacks/$name/compose.yml"); do
      st="$(docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$PROJECT-$svc" 2>/dev/null || echo "missing none")"
      case "$st" in
        "running healthy"|"running none") ;;
        *) all=0 ;;
      esac
    done
    [[ $all -eq 1 ]] && { ok=1; break; }
    sleep 3
  done
  took=$(( $(date +%s) - start ))
  if [[ $ok -eq 1 ]]; then
    echo "  ✔ up in ${took}s"; pass+=("$name ${took}s")
  else
    echo "  ✘ not healthy after ${TIMEOUT}s"; fail+=("$name (health)")
    for svc in $(services_of "$HOME/.infrapack/stacks/$name/compose.yml"); do
      echo "  --- $svc: $(docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' "$PROJECT-$svc" 2>/dev/null)"
      docker logs --tail 15 "$PROJECT-$svc" 2>&1 | sed 's/^/      /'
    done
  fi
  "$IP" uninstall "$name" --purge >/dev/null 2>&1
  if [[ "${PRUNE:-0}" == 1 ]]; then
    docker image prune -af --filter "label!=keep" >/dev/null 2>&1 || true
    docker builder prune -af >/dev/null 2>&1 || true
  fi
done

printf '\n\033[1mResults\033[0m\n'
for p in "${pass[@]+"${pass[@]}"}"; do printf '  \033[32m✔\033[0m %s\n' "$p"; done
for f in "${fail[@]+"${fail[@]}"}"; do printf '  \033[31m✘\033[0m %s\n' "$f"; done
[[ ${#fail[@]} -eq 0 ]]
