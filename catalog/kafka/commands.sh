# infrapack kafka <command>
# @cmd topics                          list topics
# @cmd describe [topic]                describe topics
# @cmd create <topic> [partitions]     create a topic
# @cmd delete <topic>                  delete a topic
# @cmd produce <topic>                 interactive console producer
# @cmd consume <topic> [--from-beginning]  console consumer
# @cmd groups                          list consumer groups
_k() { docker exec -i infrapack-kafka "/opt/kafka/bin/$1" --bootstrap-server localhost:9092 "${@:2}"; }
_kt() { docker exec $DOCKER_TTY infrapack-kafka "/opt/kafka/bin/$1" --bootstrap-server localhost:9092 "${@:2}"; }
cmd_topics()   { _k kafka-topics.sh --list; }
cmd_describe() { _k kafka-topics.sh --describe ${1:+--topic "$1"}; }
cmd_create()   { [[ $# -ge 1 ]] || die "usage: infrapack kafka create <topic> [partitions]"
                 _k kafka-topics.sh --create --if-not-exists --topic "$1" --partitions "${2:-$KAFKA_NUM_PARTITIONS}" --replication-factor 1; }
cmd_delete()   { [[ $# -ge 1 ]] || die "usage: infrapack kafka delete <topic>"; _k kafka-topics.sh --delete --topic "$1"; }
cmd_produce()  { [[ $# -ge 1 ]] || die "usage: infrapack kafka produce <topic>"; _kt kafka-console-producer.sh --topic "$1"; }
cmd_consume()  { [[ $# -ge 1 ]] || die "usage: infrapack kafka consume <topic> [--from-beginning]"; _kt kafka-console-consumer.sh --topic "$@"; }
cmd_groups()   { _k kafka-consumer-groups.sh --list; }
