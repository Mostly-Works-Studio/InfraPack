#!/usr/bin/env bash
# MySQL only reads MYSQL_* when its data directory is first created, so a
# credential change has to be applied to the running server by hand, then
# CloudBeaver's saved connection re-pointed at it. The console passes the
# previous values as OLD_MYSQL_ROOT_PASSWORD / OLD_MYSQL_USER.
set -euo pipefail
source "$STACK_DIR/commands.sh"
cmd_sync
cmd_reseed
