upstream unibpm_frontend {
  server unibpm-frontend:80;
}

upstream keycloak_upstream {
  server keycloak:8080;
}

upstream camunda_upstream {
  server camunda-bpm-7:8080;
}

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

  client_max_body_size 100m;

  # websockets
  location ^~ /stomp {
    proxy_pass http://unibpm_frontend;
    proxy_http_version 1.1;

    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";

    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP $remote_addr;

    proxy_read_timeout 86400;
    proxy_send_timeout 86400;
  }

  location / {
    proxy_pass http://unibpm_frontend;
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
    proxy_pass http://keycloak_upstream${KEYCLOAK_PATH}/;
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
    proxy_pass http://camunda_upstream;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP $remote_addr;
  }
}
