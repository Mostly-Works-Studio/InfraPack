# infrapack mariadb <command>
# @cmd shell [db]     open a mariadb client (root)
cmd_shell() { docker exec $DOCKER_TTY infrapack-mariadb mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" "${1:-$MARIADB_DATABASE}"; }
