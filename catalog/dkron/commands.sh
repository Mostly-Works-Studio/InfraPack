# infrapack dkron <command>
# @cmd jobs                                  list jobs
# @cmd add <name> "<cron>" "<shell command>"  add a shell job   (infrapack dkron add hello "@every 1m" "echo hi")
cmd_jobs() { curl -s "http://localhost:${DKRON_PORT}/v1/jobs" | tr ',{' '\n\n' | grep -E '"(name|schedule|status)"' | sed 's/^ *//'; }
cmd_add()  { [[ $# -ge 3 ]] || die 'usage: infrapack dkron add <name> "<cron>" "<command>"'
             curl -s -X POST "http://localhost:${DKRON_PORT}/v1/jobs" -H 'Content-Type: application/json' \
               -d "{\"name\":\"$1\",\"schedule\":\"$2\",\"executor\":\"shell\",\"executor_config\":{\"command\":\"$3\"}}" >/dev/null && ok "job $1 added"; }
