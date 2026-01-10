#!/bin/sh
curl --fail --silent http://localhost/healthz || exit 1
