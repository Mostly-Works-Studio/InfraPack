# infrapack maestro <command>
# @cmd sample          push and start the upstream sample workflow, print its status
# @cmd rebuild         rebuild the image from MAESTRO_REF and restart
# @cmd workflows       list workflow ids
_api() { curl -s -H 'user: infrapack' -H 'Content-Type: application/json' "http://localhost:${MAESTRO_PORT}$1" "${@:2}"; }
cmd_sample() {
  local def; def="$(curl -fsSL https://raw.githubusercontent.com/Netflix/maestro/main/maestro-server/src/test/resources/samples/sample-dag-test-1.json)" || die "could not fetch the sample"
  _api /api/v3/workflows -X POST -d "$def" >/dev/null && ok "workflow sample-dag-test-1 pushed"
  _api /api/v3/workflows/sample-dag-test-1/versions/latest/actions/start -X POST -d '{"initiator":{"type":"manual"}}' >/dev/null && ok "started"
  sleep 3; _api /api/v3/workflows/sample-dag-test-1/instances/1/runs/1 | tr ',' '\n' | grep -E '"status"' | head -3
}
cmd_rebuild()   { docker compose --project-name infrapack --project-directory "$INFRAPACK_HOME" -f "$INFRAPACK_HOME/stacks/maestro/compose.yml" build --no-cache maestro && infrapack restart maestro; }
cmd_workflows() { _api '/api/v3/workflows?limit=50' | tr ',{' '\n\n' | grep -oE '"(workflow_id|id)": *"[^"]+"' | sed -E 's/.*: *"//; s/"$//' | sort -u || true; }
