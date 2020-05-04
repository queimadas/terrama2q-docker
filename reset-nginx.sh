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
  echo "    cp .env-external .env"
  echo "Para configurações pré-definidas de acesso interno:"
  echo "    cp .env-internal .env"
  exit 1
fi
apply_env .env

for image in ${NGINX_CONF_DIR}/conf.d/terrama2q.conf; do
  sed -e 's!{{\s\?\([_A-Z]\+\)\s\?}}!$\1!g' \
      "${image}" > "${image}.base"
  parse ${image}.base
done

docker stop $(docker ps -a | grep 'terrama2_nginx' | awk '{ print $1}')
docker rm $(docker ps -a | grep 'terrama2_nginx' | awk '{ print $1}')

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

WEBAPP_PORT=${PUBLIC_PORT}
WEBMONITOR_PORT=${PUBLIC_PORT}
GEOSERVER_PORT=${PUBLIC_PORT}
GEOSERVER_HOST=${PUBLIC_HOSTNAME}

echo 'Instâcias TerraMA2'
docker ps -a | grep 'terrama2_.*'

cat << EOF

Endereços das aplicações

TerraMA2 Monitor: ${PUBLIC_PROTOCOL}${PUBLIC_HOSTNAME}:${WEBMONITOR_PORT}${PUBLIC_PATH}${WEBMONITOR_PATH}/
TerraMA2 Admin:   ${PUBLIC_PROTOCOL}${PUBLIC_HOSTNAME}:${WEBAPP_PORT}${PUBLIC_PATH}${WEBAPP_PATH}/
Geoserver:        ${GEOSERVER_PROTOCOL}://${GEOSERVER_HOST}:${GEOSERVER_PORT}${GEOSERVER_URL}
EOF
