# infrapack mssql <command>
# @cmd sqlcmd [args]     interactive sqlcmd as sa
cmd_sqlcmd() { docker exec $DOCKER_TTY infrapack-mssql /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "$MSSQL_SA_PASSWORD" "$@"; }
