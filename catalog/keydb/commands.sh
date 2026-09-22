# infrapack keydb <command>
# @cmd cli [args]     keydb-cli inside the container
cmd_cli() { docker exec $DOCKER_TTY infrapack-keydb keydb-cli "$@"; }
