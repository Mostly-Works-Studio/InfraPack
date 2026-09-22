# infrapack pgvector <command>
# @cmd psql [db]      open psql
cmd_psql() { docker exec $DOCKER_TTY infrapack-pgvector psql -U "$PGVECTOR_USER" "${1:-$PGVECTOR_DATABASE}"; }
