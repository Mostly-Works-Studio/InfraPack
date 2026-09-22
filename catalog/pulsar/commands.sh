# infrapack pulsar <command>
# @cmd admin [args]    pulsar-admin inside the container   (infrapack pulsar admin topics list public/default)
cmd_admin() { docker exec $DOCKER_TTY infrapack-pulsar bin/pulsar-admin "$@"; }
