# infrapack neo4j <command>
# @cmd cypher         open cypher-shell
cmd_cypher() { docker exec $DOCKER_TTY infrapack-neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" "$@"; }
