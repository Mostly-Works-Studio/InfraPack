# infrapack cassandra <command>
# @cmd cqlsh [args]     open cqlsh
cmd_cqlsh() { docker exec $DOCKER_TTY infrapack-cassandra cqlsh "$@"; }
