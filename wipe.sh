#!/bin/bash -x

docker stop $(docker ps -a | grep 'terrama2_.*' | awk '{ print $1}')
docker rm $(docker ps -a | grep 'terrama2_.*' | awk '{ print $1}')
