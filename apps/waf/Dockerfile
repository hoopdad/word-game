FROM owasp/modsecurity-crs:nginx-alpine

# Overwrite the OWASP single-backend template with our path-based multi-backend config.
# Template location in this image: /etc/nginx/templates/conf.d/default.conf.template
# Docker COPY overwrites the file in place; no rm needed.
COPY default.conf.template /etc/nginx/templates/conf.d/default.conf.template
