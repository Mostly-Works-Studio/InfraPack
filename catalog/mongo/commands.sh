# infrapack mongo <command>
# @cmd shell [db]     open mongosh
cmd_shell() { docker exec $DOCKER_TTY infrapack-mongo mongosh "${1:-test}"; }
