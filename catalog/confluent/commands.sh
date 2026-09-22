# infrapack confluent <command>
# @cmd topics                      list topics
# @cmd create <topic> [partitions] create a topic
# @cmd subjects                    list Schema Registry subjects
# @cmd connectors                  list Kafka Connect connectors
# @cmd hub <owner/connector:ver>   install a connector from Confluent Hub into the Connect worker, then restart it
# @cmd ksql                        interactive ksqlDB CLI
_k() { docker exec -i infrapack-confluent "$1" --bootstrap-server localhost:9092 "${@:2}"; }
cmd_topics()     { _k kafka-topics --list; }
cmd_create()     { [[ $# -ge 1 ]] || die "usage: infrapack confluent create <topic> [partitions]"; _k kafka-topics --create --if-not-exists --topic "$1" --partitions "${2:-3}" --replication-factor 1; }
cmd_subjects()   { curl -s "http://localhost:${CONFLUENT_SCHEMA_PORT}/subjects"; echo; }
cmd_connectors() { curl -s "http://localhost:${CONFLUENT_CONNECT_PORT}/connectors?expand=status" | tr ',' '\n' | grep -E '"(name|state)"' | sed 's/^ *//'; }
cmd_hub()        { [[ $# -ge 1 ]] || die "usage: infrapack confluent hub <owner/connector:version>"
                   docker exec -i infrapack-confluent-connect confluent-hub install --no-prompt --component-dir /data/plugins "$1" && docker restart infrapack-confluent-connect >/dev/null && ok "installed $1 — Connect restarting"; }
cmd_ksql()       { docker run --rm $DOCKER_TTY --network infrapack confluentinc/cp-ksqldb-cli:${CONFLUENT_KSQL_CLI_VERSION:-8.0.8} ksql http://confluent-ksqldb:8088; }
