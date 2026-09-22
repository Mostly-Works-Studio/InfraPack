# infrapack airflow <command>
# @cmd cli [args]     airflow CLI inside the container   (infrapack airflow cli dags list)
cmd_cli() { docker exec $DOCKER_TTY infrapack-airflow airflow "$@"; }
