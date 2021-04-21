#!/bin/bash

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

function apply_env() {
  eval $(egrep -v '^#' $1 | xargs)
}

apply_env .env.default
if [ ! -f '.env' ]; then
  echo "Arquivo env não existe. Configure-o para prosseguir."
  echo
  echo "Para configurações pré-definidas de acesso externo:"
  echo "\tcp .env-external .env"
  echo "Para configurações pré-definidas de acesso interno:"
  echo "\tcp .env-internal .env"
  exit 1
fi
apply_env .env

GIT=$(which git)
is_valid $? "Git must be installed. ${GIT_LINK}"

DOCKER=$(which docker)
is_valid $? "Docker must be installed. ${DOCKER_LINK}"

DOCKER_COMPOSE=$(which docker-compose)
is_valid $? "Docker-compose must be installed. ${DOCKER_COMPOSE_LINK}"

if [ ! -d ${TERRAMA2_DOCKER_DIR} ]; then
  git clone -b ${TERRAMA2_BRANCH} ${TERRAMA2_REPO_URL} ${TERRAMA2_DOCKER_DIR}
fi

if [ ! -d ${BDQLIGHT_DOCKER_DIR} ]; then
  git clone ${BDQLIGHT_REPO_URL} ${BDQLIGHT_DOCKER_DIR}
  cp -r ${TERRAMA2_DOCKER_DIR}/bdqueimadas-light/* ${BDQLIGHT_DOCKER_DIR}/
  run_into ${BDQLIGHT_DOCKER_DIR} "docker build --tag ${BDQLIGHT_IMAGE} . --rm"
fi

for image in ${TERRAMA2_CONF_DIR}/terrama2_webapp_db.json \
             ${TERRAMA2_CONF_DIR}/terrama2_webapp_settings.json \
             ${TERRAMA2_CONF_DIR}/terrama2_webmonitor.json \
             ${NGINX_CONF_DIR}/conf.d/terrama2q.conf; do
  sed -e 's!{{\s\?\([_A-Z]\+\)\s\?}}!$\1!g' \
      "${image}" > "${image}.base"
  parse ${image}.base
done

cp ${TERRAMA2_CONF_DIR}/terrama2_webmonitor.json.base \
   ${TERRAMA2_DOCKER_DIR}/conf/terrama2_webmonitor.json
cp ${TERRAMA2_CONF_DIR}/terrama2_webapp_db.json.base \
   ${TERRAMA2_DOCKER_DIR}/conf/terrama2_webapp_db.json
cp ${TERRAMA2_CONF_DIR}/terrama2_webapp_settings.json.base \
   ${TERRAMA2_DOCKER_DIR}/conf/terrama2_webapp_settings.json.in

docker network create ${SHARED_NETWORK}

docker volume create ${SHARED_VOLUME}
docker volume create ${TERRAMA2_VOLUME}
docker volume create ${GEOSERVER_VOLUME}
docker volume create ${POSTGRES_VOLUME}
docker volume create ${BDQLIGHT_VOLUME}

if [ ${GEOSERVER_BY_DOCKER} = true ]; then
    docker run -d \
               --name ${GEOSERVER_CONTAINER} \
               --restart unless-stopped \
               --network ${SHARED_NETWORK} \
	       --user '0:1000' \
               -p 127.0.0.1:8080:8080 \
               -e GEOSERVER_URL=${GEOSERVER_URL} \
               -e GEOSERVER_DATA_DIR=${GEOSERVER_DATA_DIR} \
               -e GEOSERVER_CSRF_DISABLED=${GEOSERVER_CSRF_DISABLED} \
               -v ${TERRAMA2_VOLUME}:/data \
               -v ${SHARED_VOLUME}:/shared-data \
               -v ${GEOSERVER_VOLUME}:${GEOSERVER_DATA_DIR} \
               -v ${PWD}/${GEOSERVER_FILE_SETENV}:/usr/local/tomcat/bin/setenv.sh \
               ${GEOSERVER_IMAGE}
fi

if [ ${POSTGRES_HOST} = ${POSTGRES_CONTAINER} ]; then
    docker run -d \
               --name ${POSTGRES_CONTAINER} \
               --restart unless-stopped \
               --network ${SHARED_NETWORK} \
               -p 127.0.0.1:${POSTGRES_PORT}:5432 \
               -v ${POSTGRES_VOLUME}:/var/lib/postgresql/data \
               -v /tmp:/tmp \
	       -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
               -e POSTGRES_USER=${POSTGRES_USER} \
               -e POSTGRES_DB=${POSTGRES_DB} \
               ${POSTGRES_IMAGE}
	       
	sleep 30
	
    QUERY="CREATE EXTENSION if not exists postgis; CREATE EXTENSION if not exists unaccent; drop schema if exists tiger cascade; drop schema if exists tiger_data cascade;"
    eval "docker exec -it ${POSTGRES_CONTAINER} /usr/bin/psql -U ${POSTGRES_USER} -c \"${QUERY}\" -d ${POSTGRES_DB}"
fi

docker run -d \
           --name ${BDQLIGHT_CONTAINER} \
           --restart unless-stopped \
           --network ${SHARED_NETWORK} \
           -p 127.0.0.1:39000:39000 \
           -v ${PWD}/${BDQLIGHT_CONF_DIR}/:/opt/bdqueimadas-light/configurations/ \
           -v ${PWD}/${TERRAMA2_DOCKER_DIR}/conf/bdqueimadas-light/.pgpass:/root/.pgpass \
           -v ${BDQLIGHT_VOLUME}:/opt/bdqueimadas-light/tmp \
           ${BDQLIGHT_IMAGE}

if [ "${NGINX_UP}" = true ]; then
  docker run -d \
             --name ${NGINX_CONTAINER} \
             --restart unless-stopped \
             --network ${SHARED_NETWORK} \
             -p 0.0.0.0:${NGINX_PORT}:80 \
             -v ${PWD}/${NGINX_CONF_DIR}/nginx.conf:/etc/nginx/nginx.conf:ro \
             -v ${PWD}/${NGINX_CONF_DIR}/proxy_params:/etc/nginx/proxy_params:ro \
             -v ${PWD}/${NGINX_CONF_DIR}/wssocket_params:/etc/nginx/wssocket_params:ro \
             -v ${PWD}/${NGINX_CONF_DIR}/conf.d/terrama2q.conf.base:/etc/nginx/conf.d/terrama2q.conf:ro \
             ${NGINX_IMAGE}
fi

run_into ${TERRAMA2_DOCKER_DIR} "./configure-version.sh"
run_into ${TERRAMA2_DOCKER_DIR} "docker-compose -p terrama2 up -d"

if [ "${NGINX_UP}" = true ]; then
  WEBAPP_PORT=${NGINX_PORT}
  WEBMONITOR_PORT=${NGINX_PORT}
  GEOSERVER_PORT=${NGINX_PORT}
  GEOSERVER_HOST=${PUBLIC_HOSTNAME}
else
  WEBAPP_PORT=36000
  WEBMONITOR_PORT=36001
  GEOSERVER_PORT=8080
fi

if [ "${FORCE_LOCAL_SERVICE_CONFIG}" = true ]; then
    QUERY="UPDATE terrama2.logs logs SET \\\"user\\\" = '${POSTGRES_USER}', \\\"password\\\" = '${POSTGRES_PASSWORD}', \\\"host\\\" = '${POSTGRES_HOST}', \\\"port\\\" = '${POSTGRES_PORT}', \\\"database\\\" = '${POSTGRES_DB}' FROM terrama2.service_instances si WHERE si.name like 'Local%' AND logs.service_instance_id = si.id;"
    eval "docker exec -it ${POSTGRES_CONTAINER} /usr/bin/psql -U ${POSTGRES_USER} -c \"${QUERY}\" -d ${POSTGRES_DB}"

    CONN_STR="${GEOSERVER_PROTOCOL}://${GEOSERVER_USER}:${GEOSERVER_PASSWORD}@${GEOSERVER_HOST}:${GEOSERVER_PORT}${GEOSERVER_URL}"
    QUERY="UPDATE terrama2.service_metadata sm SET \\\"value\\\" = '${CONN_STR}' FROM terrama2.service_instances si, terrama2.service_types st WHERE st.name = 'VIEW' AND si.service_type_id = st.id AND si.name LIKE 'Local%' AND sm.service_instance_id = si.id;"
    eval "docker exec -it ${POSTGRES_CONTAINER} /usr/bin/psql -U ${POSTGRES_USER} -c \"${QUERY}\" -d ${POSTGRES_DB}"

    QUERY="SELECT sm.* FROM terrama2.service_metadata sm, terrama2.service_instances si, terrama2.service_types st WHERE st.name = 'VIEW' AND si.service_type_id = st.id AND si.name LIKE 'Local%' AND sm.service_instance_id = si.id;"
    eval "docker exec -it ${POSTGRES_CONTAINER} /usr/bin/psql -U ${POSTGRES_USER} -c \"${QUERY}\" -d ${POSTGRES_DB}"
fi

if [ "${FORCE_RESTART_AFTER_CONFIG}" = true ]; then
    docker restart $(docker ps -a | grep 'terrama2_.*' | awk '{ print $1 }')
fi

echo 'Instâcias TerraMA2'
docker ps -a | grep 'terrama2_.*'

cat << EOF

Endereços das aplicações

TerraMA2 Monitor: ${PUBLIC_PROTOCOL}${PUBLIC_HOSTNAME}:${WEBMONITOR_PORT}${PUBLIC_PATH}${WEBMONITOR_PATH}/
TerraMA2 Admin:   ${PUBLIC_PROTOCOL}${PUBLIC_HOSTNAME}:${WEBAPP_PORT}${PUBLIC_PATH}${WEBAPP_PATH}/
Geoserver:        ${GEOSERVER_PROTOCOL}://${GEOSERVER_HOST}:${GEOSERVER_PORT}${GEOSERVER_URL}
EOF
