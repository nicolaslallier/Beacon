#!/bin/sh
set -e

# Define variables to substitute
export DOLLAR='$'
# shellcheck disable=SC2016
envsubst '${UPSTREAM_WEB_HOST} ${UPSTREAM_WEB_PORT} ${UPSTREAM_API_HOST} ${UPSTREAM_API_PORT} ${UPSTREAM_GRAFANA_HOST} ${UPSTREAM_GRAFANA_PORT} ${MAX_BODY_SIZE} ${GZIP_ENABLED} ${DOLLAR}' \
  < /etc/nginx/nginx.conf.template \
  > /etc/nginx/nginx.conf

exec "$@"
