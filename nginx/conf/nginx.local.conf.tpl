server {
    listen 80;
    server_name localhost;

    # Frontend
    location / {
        proxy_pass http://unibpm-frontend:80;
    }

    # Keycloak under /keycloak
    location ${KEYCLOAK_PATH}/ {
        proxy_pass http://keycloak:${KEYCLOAK_HTTP_PORT}${KEYCLOAK_PATH}/;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # Camunda under /camunda
    location ${CAMUNDA_PATH}/ {
        rewrite ^${CAMUNDA_PATH}/(.*)$ /$1 break;
        proxy_pass http://camunda-bpm-7:8080/;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
