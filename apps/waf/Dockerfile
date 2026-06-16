FROM owasp/modsecurity-crs:nginx-alpine

# 99-wordgame-config.sh runs last in the entrypoint chain (sort order > 93).
# It overwrites conf.d/default.conf with our multi-backend routing config
# using WEB_UPSTREAM and API_UPSTREAM env vars — no interaction with the
# OWASP template/envsubst pipeline.
COPY 99-wordgame-config.sh /docker-entrypoint.d/99-wordgame-config.sh
RUN chmod +x /docker-entrypoint.d/99-wordgame-config.sh
