# infrapack dragonfly <command>
# @cmd cli [args]     redis-cli inside the container
cmd_cli() { docker exec $DOCKER_TTY infrapack-dragonfly redis-cli "$@"; }
