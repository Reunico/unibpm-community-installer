server {
    listen 80;
    server_name localhost;

    # UniBPM UI (SPA)
    location / {
        proxy_pass http://unibpm-frontend:80;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $remote_addr;
    }

    # Keycloak is hosted under KEYCLOAK_PATH (default: /keycloak)
    location ${KEYCLOAK_PATH}/ {
        proxy_pass http://keycloak:${KEYCLOAK_HTTP_PORT}${KEYCLOAK_PATH}/;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Prefix ${KEYCLOAK_PATH};
    }

    # Camunda UI is hosted under CAMUNDA_CONTEXT_PATH (default: /camunda)
    location ${CAMUNDA_CONTEXT_PATH}/ {
        proxy_pass http://camunda-bpm-7:8080${CAMUNDA_CONTEXT_PATH}/;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Prefix ${CAMUNDA_CONTEXT_PATH};
    }
}
