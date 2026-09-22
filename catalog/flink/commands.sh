# infrapack flink <command>
# @cmd sql             interactive Flink SQL client
# @cmd jobs            list running jobs
# @cmd run <jar> [args] submit a jar that is visible inside the container (copy it in with docker cp)
cmd_sql()  { docker exec $DOCKER_TTY infrapack-flink bin/sql-client.sh; }
cmd_jobs() { docker exec -i infrapack-flink bin/flink list; }
cmd_run()  { [[ $# -ge 1 ]] || die "usage: infrapack flink run <jar> [args]"; docker exec -i infrapack-flink bin/flink run "$@"; }
