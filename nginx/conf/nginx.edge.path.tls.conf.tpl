server {
  listen 80;
  server_name ${UNIBPM_DOMAIN};

  location ^~ /.well-known/acme-challenge/ {
    root /var/www/certbot;
    default_type "text/plain";
    try_files $uri =404;
  }

  return 301 https://$host$request_uri;
}

server {
  listen 443 ssl http2;
  server_name ${UNIBPM_DOMAIN};

  ssl_certificate     /etc/letsencrypt/live/${CERT_PRIMARY_DOMAIN}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${CERT_PRIMARY_DOMAIN}/privkey.pem;

  # UI
  location / {
    proxy_pass http://unibpm-frontend:80;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
  }

  # Keycloak
  location ^~ ${KEYCLOAK_PATH}/ {
    proxy_pass http://keycloak:${KEYCLOAK_HTTP_PORT};
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Prefix ${KEYCLOAK_PATH};
  }

  # Camunda
  location ^~ ${CAMUNDA_PATH}/ {
    rewrite ^${CAMUNDA_PATH}/(.*)$ /$1 break;
    proxy_pass http://camunda-bpm-7:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Prefix ${CAMUNDA_PATH};
  }
}