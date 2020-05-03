#!/bin/bash

set -o pipefail

function image_id {
  docker images | awk "{if (\$1 == \"$1\" && \$2 == \"$2\") print \$3}"
}

function build_versioned_image {
  image_name="$1"
  docker_file="docker/$2"
  dockerignore_file="docker/${2%.*}.dockerignore"

  version=$(
    docker images |
    awk "{if (\$1 == \"$image_name\" && \$2 != "latest") print \$2}" |
    sort -g -r |
    head -n 1
  )

  if [ "$version" == "" ]; then
    next_version=1
  else
    this_version=$(image_id $image_name $version)
    next_version=$(($version+1))
  fi

  tmp_repository_name="tmp_$image_name"
  tmp_image_version=$(uuidgen)

  if [ -f .dockerignore ]; then rm .dockerignore; fi
  if [ -f $dockerignore_file ]; then cp -rp $dockerignore_file .dockerignore; fi
  docker build -f="$docker_file" -t "$tmp_repository_name:$tmp_image_version" . \
   || {
    exit_code="$?"
    if [ -f .dockerignore ]; then rm .dockerignore; fi
    exit $exit_code
   }

  image_id=$(image_id $tmp_repository_name $tmp_image_version)

  if [ "$this_version" == "$image_id" ]; then
    docker rmi "$image_name:latest"
    docker tag $image_id "$image_name:latest"
    echo "No changes, using $image_name:$version"
  else
    echo "Built $image_name:$next_version"
    docker tag $image_id "$image_name:$next_version"
    docker rmi "$image_name:latest"
    docker tag $image_id "$image_name:latest"
  fi
  docker rmi "$tmp_repository_name:$tmp_image_version" > /dev/null

  for old_version in $(
    docker images |
    awk "{if (\$1 == \"$image_name\" && \$2 != \"latest\") print \$2}" |
    sort -g -r |
    tail -n+3
  ); do
    docker rmi "$image_name:$old_version"
  done

  stopped_containers=$(docker ps -a | tail -n+2 | grep -v Up | awk '{print $1}')
  if [ "$stopped_containers" != "" ]; then
    docker rm "$stopped_containers" > /dev/null || true
  fi

  dangling_images=$(docker images -f "dangling=true" -q)
  for image in $dangling_images; do
    docker rmi $image > /dev/null || true
  done
}

function copy_release {
  mkdir -p tmp
  rm -rf tmp/* || true
  id=$(docker create "erlangelist/site-builder:latest" /bin/sh)
  docker cp $id:/opt/app/site/_build/prod/erlangelist-0.0.1.tar.gz ./tmp/erlangelist.tar.gz
  docker stop $id > /dev/null
  docker rm -v $id > /dev/null

  cd tmp && tar -xzf erlangelist.tar.gz && cd ..
  rm tmp/erlangelist.tar.gz
}

cd $(dirname ${BASH_SOURCE[0]})/..

build_versioned_image erlangelist/site-builder site-builder.dockerfile
copy_release
build_versioned_image erlangelist/site site.dockerfile
