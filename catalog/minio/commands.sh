# infrapack minio <command>
# @cmd mc [args]        MinIO client against the local server (alias "local")
# @cmd mb <bucket>      create a bucket
cmd_mc() { docker exec $DOCKER_TTY infrapack-minio mc "$@"; }
cmd_mb() { [[ $# -ge 1 ]] || die "usage: infrapack minio mb <bucket>"; docker exec -i infrapack-minio mc mb --ignore-existing "local/$1"; }
