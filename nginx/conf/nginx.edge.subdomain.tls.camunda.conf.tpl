server {
    listen 80;
    server_name ${UNIBPM_DOMAIN} ${KEYCLOAK_DOMAIN} ${CAMUNDA_DOMAIN};
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://$host$request_uri; }
}
server {
    listen 443 ssl;
    server_name ${UNIBPM_DOMAIN};
    ssl_certificate     /etc/letsencrypt/live/${CERT_PRIMARY_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${CERT_PRIMARY_DOMAIN}/privkey.pem;
    location / {
        proxy_pass http://unibpm-frontend:80;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
server {
    listen 443 ssl;
    server_name ${KEYCLOAK_DOMAIN};
    ssl_certificate     /etc/letsencrypt/live/${CERT_PRIMARY_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${CERT_PRIMARY_DOMAIN}/privkey.pem;
    location / {
        proxy_pass http://keycloak:${KEYCLOAK_HTTP_PORT}${KEYCLOAK_PATH};
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
server {
    listen 443 ssl;
    server_name ${CAMUNDA_DOMAIN};
    ssl_certificate     /etc/letsencrypt/live/${CERT_PRIMARY_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${CERT_PRIMARY_DOMAIN}/privkey.pem;
    location / {
        proxy_pass http://camunda-bpm-7:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
