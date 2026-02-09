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

  location ^~ /stomp/ {
    proxy_pass http://unibpm:8099/stomp/;
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

  location ^~ ${KEYCLOAK_PATH}/ {
      proxy_pass http://keycloak_upstream;
      proxy_set_header Host $host;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-Prefix ${KEYCLOAK_PATH};
    }

    location ^~ ${CAMUNDA_PATH}/ {
      proxy_pass http://camunda_upstream;
      proxy_set_header Host $host;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-Prefix ${CAMUNDA_PATH};
    }
}
