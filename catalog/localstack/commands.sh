# infrapack localstack <command>
# @cmd aws [args]       awslocal inside the container   (infrapack localstack aws s3 mb s3://demo)
# @cmd health           which services are running
cmd_aws()    { docker exec $DOCKER_TTY infrapack-localstack awslocal "$@"; }
cmd_health() { docker exec -i infrapack-localstack curl -s localhost:4566/_localstack/health; echo; }
