# infrapack mysql <command>
# @cmd shell [db]      open a mysql client (root)
# @cmd sync            apply the .env credentials to the running server
# @cmd reseed          re-point CloudBeaver at the current credentials

_auth_ok() { docker exec -i infrapack-mysql mysql -uroot -p"$1" -e 'SELECT 1' >/dev/null 2>&1; }

cmd_shell() {
  docker exec $DOCKER_TTY infrapack-mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "${1:-$MYSQL_DATABASE}"
}

cmd_sync() {
  running mysql || { ok "MySQL is not running — nothing to sync"; return; }
  local auth
  if _auth_ok "$MYSQL_ROOT_PASSWORD"; then auth="$MYSQL_ROOT_PASSWORD"
  elif [[ -n "${OLD_MYSQL_ROOT_PASSWORD:-}" ]] && _auth_ok "$OLD_MYSQL_ROOT_PASSWORD"; then auth="$OLD_MYSQL_ROOT_PASSWORD"
  else die "cannot authenticate to MySQL as root — 'infrapack reset mysql' starts it fresh"; fi
  local sql=""
  sql+="CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  sql+="CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';"
  sql+="ALTER USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';"
  sql+="GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_USER}'@'%' WITH GRANT OPTION;"
  if [[ -n "${OLD_MYSQL_USER:-}" && "${OLD_MYSQL_USER}" != "$MYSQL_USER" ]]; then
    sql+="DROP USER IF EXISTS '${OLD_MYSQL_USER}'@'%';"
  fi
  sql+="ALTER USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
  sql+="ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
  sql+="FLUSH PRIVILEGES;"
  docker exec -i infrapack-mysql mysql -uroot -p"$auth" -e "$sql" 2>/dev/null \
    && ok "MySQL users and database match the settings" || die "failed to apply MySQL changes"
}

cmd_reseed() {
  bash "$STACK_DIR/hooks/pre-up.sh"
  if running mysql-ui; then
    docker exec -u root infrapack-mysql-ui sh -c '
      d=/opt/cloudbeaver/workspace/GlobalConfiguration/.dbeaver
      mkdir -p "$d"
      cp /opt/cloudbeaver/conf/initial-data-sources.conf "$d/data-sources.json"
      chown -R dbeaver:dbeaver /opt/cloudbeaver/workspace/GlobalConfiguration' >/dev/null
    docker restart infrapack-mysql-ui >/dev/null
    ok "CloudBeaver connection re-synced"
  else
    ok "connection file updated (CloudBeaver is not running)"
  fi
}
