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

function parse() {
  truncate /tmp/tmp.sh --size 0
  echo 'eval $(egrep -v '^\#' .env.default | xargs)' >> /tmp/tmp.sh
  echo 'eval $(egrep -v '^\#' .env | xargs)' >> /tmp/tmp.sh
  echo 'cat <<EOF' >> /tmp/tmp.sh
  cat "$1" >> /tmp/tmp.sh
  echo 'EOF' >> /tmp/tmp.sh
  bash /tmp/tmp.sh > "$1"
  rm /tmp/tmp.sh
}

function apply_context() {
  eval $(egrep -v '^#' $1 | xargs)
}

apply_context .env.default
if [ ! -f '.env' ]; then
  echo "Arquivo env não existe. Configure-o para prosseguir."
  exit 1
fi
apply_context .env


GIT=$(which git)
is_valid $? "Git must be installed. ${GIT_LINK}"

DOCKER=$(which docker)
is_valid $? "Docker must be installed. ${DOCKER_LINK}"

DOCKER_COMPOSE=$(which docker-compose)
is_valid $? "Docker-compose must be installed. ${DOCKER_COMPOSE_LINK}"

if [ ! -d ${TERRAMA2_DOCKER_DIR} ]; then
  git clone ${TERRAMA2_REPO_URL} ${TERRAMA2_DOCKER_DIR}
fi

if [ ! -d ${BDQLIGHT_DOCKER_DIR} ]; then
  git clone ${BDQLIGHT_REPO_URL} ${BDQLIGHT_DOCKER_DIR}
fi

for image in ${TERRAMA2_CONF_DIR}/terrama2_webapp.json.in \
             ${TERRAMA2_CONF_DIR}/terrama2_webmonitor.json; do
  sed -e 's!{{\s\?\([_A-Z]\+\)\s\?}}!$\1!g' \
      "${image}" > "${image}.base"
  parse ${image}.base
done

cp ${TERRAMA2_CONF_DIR}/terrama2_webapp.json.in.base \
   ${TERRAMA2_DOCKER_DIR}/conf/terrama2_webapp.json.in
cp ${TERRAMA2_CONF_DIR}/terrama2_webmonitor.json.base \
   ${TERRAMA2_DOCKER_DIR}/conf/terrama2_webmonitor.json

cp -r ${TERRAMA2_DOCKER_DIR}/bdqueimadas-light/* ${BDQLIGHT_DOCKER_DIR}/
run_into ${BDQLIGHT_DOCKER_DIR} "docker build --tag ${BDQLIGHT_IMAGE} . --rm"

docker network create ${SHARED_NETWORK}

docker volume create ${SHARED_VOLUME}
docker volume create ${TERRAMA2_VOLUME}
docker volume create ${GEOSERVER_VOLUME}
docker volume create ${POSTGRES_VOLUME}
docker volume create ${BDQLIGHT_VOLUME}

docker run -d \
           --name ${GEOSERVER_CONTAINER} \
           --restart unless-stopped \
           --network ${SHARED_NETWORK} \
           -p 127.0.0.1:8080:8080 \
           -e GEOSERVER_URL=${GEOSERVER_URL} \
           -e GEOSERVER_DATA_DIR=${GEOSERVER_DATA_DIR} \
           -v ${TERRAMA2_VOLUME}:/data \
           -v ${SHARED_VOLUME}:/shared-data \
           -v ${GEOSERVER_VOLUME}:${GEOSERVER_DATA_DIR} \
           -v ${PWD}/${TERRAMA2_DOCKER_DIR}/conf/terrama2_geoserver_setenv.sh:/usr/local/tomcat/bin/setenv.sh \
           ${GEOSERVER_IMAGE}

docker run -d \
           --name ${POSTGRES_CONTAINER} \
           --restart unless-stopped \
           --network ${SHARED_NETWORK} \
           -p 127.0.0.1:${POSTGRES_PORT}:5432 \
           -v ${POSTGRES_VOLUME}:/var/lib/postgresql/data \
           -e POSTGRES_USER=${POSTGRES_USER} \
           -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
           -e POSTGRES_USER=${POSTGRES_USER} \
           -e POSTGRES_DB=${POSTGRES_DB} \
           ${POSTGRES_IMAGE}

docker run -d \
           --name ${BDQLIGHT_CONTAINER} \
           --restart unless-stopped \
           --network ${SHARED_NETWORK} \
           -p 127.0.0.1:39000:39000 \
           -v ${PWD}/${BDQLIGHT_CONF_DIR}/:/opt/bdqueimadas-light/configurations/ \
           -v ${PWD}/${TERRAMA2_DOCKER_DIR}/conf/bdqueimadas-light/.pgpass:/root/.pgpass \
           -v ${BDQLIGHT_VOLUME}:/opt/bdqueimadas-light/tmp \
           ${BDQLIGHT_IMAGE}

docker run -d \
           --name ${NGINX_CONTAINER} \
           --restart unless-stopped \
           --network ${SHARED_NETWORK} \
           -p 0.0.0.0:${PUBLIC_PORT}:80 \
           -v ${PWD}/${NGINX_CONF_DIR}/nginx.conf:/etc/nginx/nginx.conf:ro \
           -v ${PWD}/${NGINX_CONF_DIR}/proxy_params:/etc/nginx/proxy_params:ro \
           -v ${PWD}/${NGINX_CONF_DIR}/wssocket_params:/etc/nginx/wssocket_params:ro \
           -v ${PWD}/${NGINX_CONF_DIR}/conf.d:/etc/nginx/conf.d:ro \
           ${NGINX_IMAGE}

run_into ${TERRAMA2_DOCKER_DIR} "./configure-version.sh"
run_into ${TERRAMA2_DOCKER_DIR} "docker-compose -p terrama2 up -d"
