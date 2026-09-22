# infrapack cockroachdb <command>
# @cmd sql            open the cockroach SQL shell
cmd_sql() { docker exec $DOCKER_TTY infrapack-cockroachdb cockroach sql --insecure "$@"; }
