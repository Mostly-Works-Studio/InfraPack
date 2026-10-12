# infrapack seaweedfs <command>
# @cmd shell [args]      weed shell against the local cluster (s3.bucket.list, s3.user.list, volume.list …)
# @cmd mb <bucket>       create a bucket
# @cmd buckets           list buckets
cmd_shell()   { docker exec $DOCKER_TTY infrapack-seaweedfs weed shell -master=seaweedfs:9333 "$@"; }
cmd_mb()      { [[ $# -ge 1 ]] || die "usage: infrapack seaweedfs mb <bucket>"; echo "s3.bucket.create -name $1" | docker exec -i infrapack-seaweedfs weed shell -master=seaweedfs:9333; }
cmd_buckets() { echo "s3.bucket.list" | docker exec -i infrapack-seaweedfs weed shell -master=seaweedfs:9333; }
