server {
    listen 80;
    server_name ${UNIBPM_DOMAIN};
    location / {
        proxy_pass http://unibpm-frontend:80;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto http;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
server {
    listen 80;
    server_name ${KEYCLOAK_DOMAIN};
    location / {
        proxy_pass http://keycloak:${KEYCLOAK_HTTP_PORT}${KEYCLOAK_PATH};
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto http;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
server {
    listen 80;
    server_name ${CAMUNDA_DOMAIN};
    location / {
        proxy_pass http://camunda-bpm-7:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto http;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
