#!/bin/sh
set -e

# Define variables to substitute
export DOLLAR='$'
envsubst '${UPSTREAM_WEB_HOST} ${UPSTREAM_WEB_PORT} ${UPSTREAM_API_HOST} ${UPSTREAM_API_PORT} ${MAX_BODY_SIZE} ${GZIP_ENABLED} ${DOLLAR}' \
  < /etc/nginx/nginx.conf.template \
  > /etc/nginx/nginx.conf

exec "$@"
