# infrapack rabbitmq <command>
# @cmd queues         list queues
# @cmd ctl [args]     rabbitmqctl inside the container
cmd_queues() { docker exec -i infrapack-rabbitmq rabbitmqctl list_queues name messages consumers; }
cmd_ctl()    { docker exec $DOCKER_TTY infrapack-rabbitmq rabbitmqctl "$@"; }
