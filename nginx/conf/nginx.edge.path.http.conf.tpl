server {
  listen 80;
  server_name ${UNIBPM_DOMAIN};

  # ACME challenge (Let's Encrypt)
  location ^~ /.well-known/acme-challenge/ {
    root /var/www/certbot;
    default_type "text/plain";
    try_files $uri =404;
  }

  # UI (frontend)
  location / {
    proxy_pass http://unibpm-frontend:80;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }

  # Keycloak is configured with relative path /keycloak
  location ^~ ${KEYCLOAK_PATH}/ {
    proxy_pass http://keycloak:${KEYCLOAK_HTTP_PORT};
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Prefix ${KEYCLOAK_PATH};
  }

  # Camunda under /camunda (we strip prefix)
  location ^~ ${CAMUNDA_PATH}/ {
    rewrite ^${CAMUNDA_PATH}/(.*)$ /$1 break;
    proxy_pass http://camunda-bpm-7:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Prefix ${CAMUNDA_PATH};
  }
}