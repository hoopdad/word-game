FROM owasp/modsecurity-crs:nginx-alpine

# Remove the default single-backend proxy template; we use path-based routing.
RUN rm -f /etc/nginx/templates/default.conf.template 2>/dev/null || true

# Our multi-backend routing template processed by envsubst at startup.
COPY default.conf.template /etc/nginx/templates/default.conf.template
