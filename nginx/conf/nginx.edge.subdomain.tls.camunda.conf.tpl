server {
  listen 80;
  server_name ${UNIBPM_DOMAIN};

  location ^~ /.well-known/acme-challenge/ {
      root /var/www/certbot;
      default_type "text/plain";
      try_files $uri =404;
  }

  location / { return 301 https://$host$request_uri; }
}

server {
  listen 443 ssl;
  server_name ${UNIBPM_DOMAIN};

  ssl_certificate     /etc/letsencrypt/live/${CERT_PRIMARY_DOMAIN}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${CERT_PRIMARY_DOMAIN}/privkey.pem;

  location / {
    proxy_pass http://unibpm-frontend:${FRONTEND_HTTP_PORT};
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP $remote_addr;
  }
}

server {
  listen 80;
  server_name ${KEYCLOAK_DOMAIN};

  location ^~ /.well-known/acme-challenge/ {
    root /var/www/certbot;
    default_type "text/plain";
    try_files $uri =404;
  }

  location / { return 301 https://$host$request_uri; }
}

server {
  listen 443 ssl;
  server_name ${KEYCLOAK_DOMAIN};

  ssl_certificate     /etc/letsencrypt/live/${CERT_PRIMARY_DOMAIN}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${CERT_PRIMARY_DOMAIN}/privkey.pem;

  location = / {
    return 301 ${KEYCLOAK_PATH}/;
  }

  location ^~ ${KEYCLOAK_PATH}/ {
    proxy_pass http://keycloak:${KEYCLOAK_HTTP_PORT}${KEYCLOAK_PATH}/;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-Prefix ${KEYCLOAK_PATH};
  }
}

server {
  listen 80;
  server_name ${CAMUNDA_DOMAIN};

  location ^~ /.well-known/acme-challenge/ {
    root /var/www/certbot;
    default_type "text/plain";
    try_files $uri =404;
  }

  location / { return 301 https://$host$request_uri; }
}

server {
  listen 443 ssl;
  server_name ${CAMUNDA_DOMAIN};

  ssl_certificate     /etc/letsencrypt/live/${CERT_PRIMARY_DOMAIN}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${CERT_PRIMARY_DOMAIN}/privkey.pem;

  location = / {
    return 302 /camunda/;
  }

  location / {
    proxy_pass http://camunda-bpm-7:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP $remote_addr;
  }
}
