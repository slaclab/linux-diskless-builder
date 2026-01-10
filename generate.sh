#!/usr/bin/env bash

set -ex

# Generate the builder docker image
cd docker && ./build.sh && cd -

# Use the docker image to build the diskless images
docker container run -ti --rm \
    --ulimit "nofile=1024:1024" \
    --mount src=${PWD}/output,target=/output,type=bind \
    --mount src=rl9-builder,target=/rl9-builder,type=volume \
    --mount src=${PWD}/scripts,target=/scripts,type=bind \
    --mount src=${PWD}/custom_files,target=/custom_files,type=bind \
    --mount src=${PWD}/VERSION,target=/VERSION,type=bind \
    rl9-builder /scripts/generate-image.sh $@
