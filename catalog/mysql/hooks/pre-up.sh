#!/usr/bin/env bash
# CloudBeaver seeds its workspace from this file on first start. Rendered
# before every start so it always reflects the current credentials.
set -euo pipefail
mkdir -p "$STACK_DIR/generated"
cat > "$STACK_DIR/generated/initial-data-sources.conf" <<CONF
{
  "folders": {},
  "connections": {
    "infrapack-mysql": {
      "provider": "mysql",
      "driver": "mysql8",
      "name": "Local MySQL",
      "description": "InfraPack MySQL container",
      "save-password": true,
      "show-system-objects": true,
      "configuration": {
        "host": "mysql",
        "port": "3306",
        "database": "${MYSQL_DATABASE:-local}",
        "url": "jdbc:mysql://mysql:3306/${MYSQL_DATABASE:-local}",
        "type": "dev",
        "auth-model": "native",
        "user": "root",
        "password": "${MYSQL_ROOT_PASSWORD:-root}"
      }
    }
  }
}
CONF
