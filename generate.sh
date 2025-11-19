#!/usr/bin/env bash

# Generate the builder docker image
cd docker && ./build.sh && cd -

# Use the docker image to build the CentOS7 diskless images
docker container run -i --rm \
    --ulimit "nofile=1024:1024" \
    --mount src=${PWD}/output,target=/output,type=bind \
    --mount src=centos7-builder,target=/centos7-builder,type=volume \
    --mount src=${PWD}/scripts,target=/scripts,type=bind \
    --mount src=${PWD}/custom_files,target=/custom_files,type=bind \
    --mount src=${PWD}/VERSION,target=/VERSION,type=bind \
    --mount src=${PWD}/Intel_LAN_drivers_Dell_R750,target=/centos7-builder/Intel_LAN_drivers_Dell_R750,type=bind \
    centos7-builder \
    /scripts/generate-image.sh $@
