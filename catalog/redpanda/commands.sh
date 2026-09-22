# infrapack redpanda <command>
# @cmd rpk [args]      rpk inside the container   (infrapack redpanda rpk topic create demo)
# @cmd topics          list topics
cmd_rpk()    { docker exec $DOCKER_TTY infrapack-redpanda rpk "$@"; }
cmd_topics() { docker exec -i infrapack-redpanda rpk topic list; }
