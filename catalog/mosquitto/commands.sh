# infrapack mosquitto <command>
# @cmd sub <topic>             subscribe and print messages
# @cmd pub <topic> <message>   publish one message
cmd_sub() { [[ $# -ge 1 ]] || die "usage: infrapack mosquitto sub <topic>"; docker exec $DOCKER_TTY infrapack-mosquitto mosquitto_sub -t "$1" -v; }
cmd_pub() { [[ $# -ge 2 ]] || die "usage: infrapack mosquitto pub <topic> <message>"; docker exec -i infrapack-mosquitto mosquitto_pub -t "$1" -m "$2"; }
