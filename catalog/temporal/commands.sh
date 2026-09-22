# infrapack temporal <command>
# @cmd cli [args]     temporal CLI inside the server container   (infrapack temporal cli workflow list)
cmd_cli() { docker exec $DOCKER_TTY infrapack-temporal temporal --address temporal:7233 "$@"; }
