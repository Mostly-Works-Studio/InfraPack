# infrapack clickhouse <command>
# @cmd client         open clickhouse-client
cmd_client() { docker exec $DOCKER_TTY infrapack-clickhouse clickhouse-client -u "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" -d "$CLICKHOUSE_DATABASE"; }
