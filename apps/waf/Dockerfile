FROM owasp/modsecurity-crs:nginx-alpine

# Replace the OWASP single-backend template with our path-based multi-backend config.
# The OWASP nginx image stores templates under conf.d/ (not directly under templates/).
RUN rm -f /etc/nginx/templates/conf.d/default.conf.template

COPY default.conf.template /etc/nginx/templates/conf.d/default.conf.template
