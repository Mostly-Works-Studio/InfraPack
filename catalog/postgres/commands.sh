# infrapack postgres <command>
# @cmd psql [db]      open psql
cmd_psql() { docker exec $DOCKER_TTY infrapack-postgres psql -U "$POSTGRES_USER" "${1:-$POSTGRES_DATABASE}"; }
