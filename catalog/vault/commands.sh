# infrapack vault <command>
# @cmd cli [args]     vault CLI as root inside the container   (infrapack vault cli kv put secret/demo k=v)
# @cmd token          print the root token
cmd_cli()   { docker exec $DOCKER_TTY -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN="$VAULT_TOKEN" infrapack-vault vault "$@"; }
cmd_token() { [[ -n "${VAULT_TOKEN:-}" ]] && echo "$VAULT_TOKEN" || die "no token yet — is vault running?"; }
