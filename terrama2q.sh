#!/bin/bash -x

function is_valid() {
  local code=$1
  local err_msg=$2

  if [ $1 -ne 0 ]; then
    echo ${err_msg}
    exit ${code}
  fi
}

function run_into() {
  local dir=$1
  local command=$2

  (cd $dir; eval ${command})
}

GIT_LINK="https://git-scm.com/book/en/v2/Getting-Started-Installing-Git"
GIT=$(which git)
is_valid $? "Git must be installed. ${GIT_LINK}"
echo "Using git from ${GIT}"

DOCKER_LINK="https://docs.docker.com/install/"
DOCKER=$(which docker)
is_valid $? "Docker must be installed. ${DOCKER_LINK}"
echo "Using docker from ${DOCKER}"

DOCKER_COMPOSE_LINK="https://docs.docker.com/compose/install/"
DOCKER_COMPOSE=$(which docker-compose)
is_valid $? "Docker-compose must be installed. ${DOCKER_COMPOSE_LINK}"
echo "Using docker-compose from ${DOCKER_COMPOSE}"

TERRAMA2_REPO_URL="https://github.com/terrama2/docker.git"
BDQLIGHT_REPO_URL="https://github.com/jonatasleon/bdqueimadas-light.git"
TERRAMA2_DOCKER_DIR="terrama2-docker"
BDQLIGHT_DOCKER_DIR="bdqlight"
NGINX_DOCKER_DIR="nginx-conf"

SHARED_VOLUME="terrama2_shared_vol"
TERRAMA2_VOLUME="terrama2_data_vol"
GEOSERVER_VOLUME="terrama2_geoserver_vol"
POSTGRES_VOLUME="terrama2_pg_vol"
BDQLIGHT_VOLUME="terrama2_bdq_vol"

TERRAMA2_NETWORK="terrama2_net"

GEOSERVER_IMAGE="terrama2/geoserver:2.11"
POSTGRES_IMAGE="mdillon/postgis"
BDQLIGHT_IMAGE="jonatasleon/bdqlight:1.0.1"
NGINX_IMAGE="nginx:latest"

GEOSERVER_CONTAINER="terrama2_geoserver"
POSTGRES_CONTAINER="terrama2_pg"
BDQLIGHT_CONTAINER="terrama2_bdq"
NGINX_CONTAINER="terrama2_nginx"

POSTGRES_PASSWORD=mysecretpassword

if [ ! -d ${TERRAMA2_DOCKER_DIR} ]; then
  git clone ${TERRAMA2_REPO_URL} ${TERRAMA2_DOCKER_DIR}
fi

if [ ! -d ${BDQLIGHT_DOCKER_DIR} ]; then
  git clone ${BDQLIGHT_REPO_URL} ${BDQLIGHT_DOCKER_DIR}
fi

cp -r ${TERRAMA2_DOCKER_DIR}/bdqueimadas-light/* ${BDQLIGHT_DOCKER_DIR}/
run_into ${BDQLIGHT_DOCKER_DIR} "docker build --tag ${BDQLIGHT_IMAGE} . --rm"

docker network create ${TERRAMA2_NETWORK}

docker volume create ${SHARED_VOLUME}
docker volume create ${TERRAMA2_VOLUME}
docker volume create ${GEOSERVER_VOLUME}
docker volume create ${POSTGRES_VOLUME}
docker volume create ${BDQLIGHT_VOLUME}

docker run -d \
           --name ${GEOSERVER_CONTAINER} \
           --restart unless-stopped \
           --network ${TERRAMA2_NETWORK} \
           -p 127.0.0.1:8080:8080 \
           -e "GEOSERVER_URL=/geoserver" \
           -e "GEOSERVER_DATA_DIR=/opt/geoserver/data_dir" \
           -v ${TERRAMA2_VOLUME}:/data \
           -v ${SHARED_VOLUME}:/shared-data \
           -v ${GEOSERVER_VOLUME}:/opt/geoserver/data_dir \
           -v ${PWD}/${TERRAMA2_DOCKER_DIR}/conf/terrama2_geoserver_setenv.sh:/usr/local/tomcat/bin/setenv.sh \
           ${GEOSERVER_IMAGE}

docker run -d \
           --name ${POSTGRES_CONTAINER} \
           --restart unless-stopped \
           --network ${TERRAMA2_NETWORK} \
           -p 127.0.0.1:5433:5432 \
           -v ${POSTGRES_VOLUME}:/var/lib/postgresql/data \
           -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
           ${POSTGRES_IMAGE}

docker run -d \
           --name ${BDQLIGHT_CONTAINER} \
           --restart unless-stopped \
           --network ${TERRAMA2_NETWORK} \
           -p 127.0.0.1:39000:39000 \
           -v ${PWD}/bdqlight-conf/:/opt/bdqueimadas-light/configurations/ \
           -v ${PWD}/${TERRAMA2_DOCKER_DIR}/conf/bdqueimadas-light/.pgpass:/root/.pgpass \
           -v ${BDQLIGHT_VOLUME}:/opt/bdqueimadas-light/tmp \
           ${BDQLIGHT_IMAGE}

docker run -d \
           --name ${NGINX_CONTAINER} \
           --restart unless-stopped \
           --network ${TERRAMA2_NETWORK} \
           -p 0.0.0.0:80:80 \
           -v ${PWD}/${NGINX_DOCKER_DIR}/nginx.conf:/etc/nginx/nginx.conf:ro \
           -v ${PWD}/${NGINX_DOCKER_DIR}/proxy_params:/etc/nginx/proxy_params:ro \
           -v ${PWD}/${NGINX_DOCKER_DIR}/wssocket_params:/etc/nginx/wssocket_params:ro \
           -v ${PWD}/${NGINX_DOCKER_DIR}/conf.d:/etc/nginx/conf.d:ro \
           ${NGINX_IMAGE}

run_into ${TERRAMA2_DOCKER_DIR} "./configure-version.sh"
run_into ${TERRAMA2_DOCKER_DIR} "docker-compose -p terrama2 up -d"
