#!/usr/bin/env bash
# After the unsealer has initialised Vault, copy the generated root token into
# the workspace settings so the console card and `infrapack vault cli` can use it.
set -euo pipefail
for _ in $(seq 1 30); do
  token="$(docker exec infrapack-vault-init sh -c 'cat /keys/init.json 2>/dev/null' | tr -d '\n ' | sed -n 's/.*"root_token":"\([^"]*\)".*/\1/p' || true)"
  if [[ -n "$token" ]]; then
    if [[ "${VAULT_TOKEN:-}" != "$token" ]]; then
      env_set VAULT_TOKEN "$token"
      ok "vault root token saved to settings"
    fi
    exit 0
  fi
  sleep 2
done
warn "vault has not finished initialising yet — the token appears on the next start"
