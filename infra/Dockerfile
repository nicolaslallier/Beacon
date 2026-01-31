FROM nginx:1.27-alpine

# Install envsubst (part of gettext) and curl
RUN apk add --no-cache gettext curl

# Copy configuration files
COPY ./infra/templates/nginx.conf.template /etc/nginx/nginx.conf.template
COPY ./infra/conf.d/ /etc/nginx/conf.d/
COPY ./infra/html/ /usr/share/nginx/html/
COPY ./scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY ./scripts/healthz.sh /usr/local/bin/healthz.sh

# Set permissions
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthz.sh

# Expose ports
EXPOSE 80 443

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
