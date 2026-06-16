#!/bin/sh
# Runs last in the OWASP nginx entrypoint chain (sort order 99 > 93 proxy-ssl step).
# Overwrites conf.d/default.conf with multi-backend routing after OWASP templates
# have already been processed. WEB_UPSTREAM and API_UPSTREAM must be set.
cat > /etc/nginx/conf.d/default.conf << NGINXEOF
server {
    listen 8080;
    server_name _;

    location ~ ^/api(/|\$) {
        proxy_pass          https://${API_UPSTREAM};
        proxy_ssl_name      ${API_UPSTREAM};
        proxy_ssl_verify    on;
        proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;
        proxy_set_header    Host              ${API_UPSTREAM};
        proxy_set_header    X-Real-IP         \$remote_addr;
        proxy_set_header    X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header    X-Forwarded-Proto \$scheme;
        proxy_read_timeout  30s;
        proxy_connect_timeout 5s;
    }

    location /healthz {
        modsecurity off;
        return 200 "ok\n";
        add_header Content-Type text/plain;
    }

    location / {
        proxy_pass          https://${WEB_UPSTREAM};
        proxy_ssl_name      ${WEB_UPSTREAM};
        proxy_ssl_verify    on;
        proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;
        proxy_set_header    Host              ${WEB_UPSTREAM};
        proxy_set_header    X-Real-IP         \$remote_addr;
        proxy_set_header    X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header    X-Forwarded-Proto \$scheme;
        proxy_read_timeout  30s;
        proxy_connect_timeout 5s;
    }
}
NGINXEOF
