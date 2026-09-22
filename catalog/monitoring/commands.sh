# infrapack monitoring <command>
# @cmd reload       reload prometheus.yml without a restart
# @cmd targets      show scrape targets and their state
cmd_reload()  { docker exec -i infrapack-prometheus wget -qO- --post-data='' http://localhost:9090/-/reload && ok "prometheus reloaded"; }
cmd_targets() { docker exec -i infrapack-prometheus wget -qO- http://localhost:9090/api/v1/targets | tr ',' '\n' | grep -E '"(scrapeUrl|health)"'; }
