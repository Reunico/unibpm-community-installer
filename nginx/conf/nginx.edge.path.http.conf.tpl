server {
  listen 80;
  server_name ${UNIBPM_DOMAIN};

  location ^~ /.well-known/acme-challenge/ {
    root /var/www/certbot;
    try_files $uri =404;
  }

  location ^~ ${KEYCLOAK_PATH}/ {
    proxy_pass http://keycloak:${KEYCLOAK_HTTP_PORT}${KEYCLOAK_PATH}/;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-Prefix ${KEYCLOAK_PATH};
  }

  location ^~ ${CAMUNDA_PATH}/ {
    proxy_pass http://camunda-bpm-7:8080/;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-Prefix ${CAMUNDA_PATH};
  }

  location / {
    proxy_pass http://unibpm-frontend:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP $remote_addr;
  }
}