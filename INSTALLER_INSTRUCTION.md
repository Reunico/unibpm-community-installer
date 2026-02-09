# UniBPM Community — Installer Instruction (операционное руководство)

Документ предназначен для инженеров, которые разворачивают дистрибутив на VM/в облаке или локально.

---

## 1) Пререквизиты

### Обязательное
- Docker Engine 20+
- Docker Compose v2 (`docker compose version`)
- Доступ к registry (если образы приватные)
- (опционально) Git — нужен только если вы скачиваете дистрибутив через `git clone`.
  Если Git не установлен, можно скачать архив релиза/ветки и распаковать.

### Для Edge+TLS
- Публичный IP VM
- Открыты порты:
    - 80/tcp (обязательно для Let’s Encrypt HTTP-01)
    - 443/tcp (для HTTPS)
- DNS A-записи на IP VM (см. ниже)

---

## 2) Состав дистрибутива

Дистрибутив запускает “всё включено” (отключение компонентов не предусмотрено):
- `postgres` (данные UniBPM и Keycloak)
- `kafka`
- `keycloak` (realm + clients импортируются из `keycloak/config`)
- `unibpm` (backend)
- `unibpm-frontend` (frontend + свой nginx внутри контейнера)
- `camunda-bpm-7`
- `nginx` (gateway для edge/DNS/HTTPS)
- `certbot` (выпуск/обновление сертификатов Let’s Encrypt — только при `ENABLE_TLS=true`)

---

## 3) Порядок запуска (как работает installer)

Запуск выполняет `install.sh`.

> `install.sh` можно запускать повторно — существующие volume и данные не удаляются.

1) Загружает `.env`
2) Вычисляет и экспортирует:
    - `PUBLIC_SCHEME` (http/https)
    - `KEYCLOAK_EXTERNAL_URL` (URL для браузера/редиректов)
3) Генерирует `generated/nginx/default.conf` из шаблонов `nginx/conf/*.tpl` (в зависимости от режима)
4) Поднимает инфраструктуру: `postgres`, `kafka`, `keycloak`
5) Запускает `prepare.sh`, который:
    - ждёт готовность realm в Keycloak
    - получает admin token
    - вытаскивает client secrets (unibpm-app, camunda-identity-service)
    - генерирует:
        - `generated/unibpm/application.yaml`
        - `generated/camunda/application.yml`
6) Поднимает `unibpm`, `camunda-bpm-7`, `unibpm-frontend`
7) Если `DEPLOY_MODE=edge` — поднимает `nginx`
8) Если `DEPLOY_MODE=edge` и `ENABLE_TLS=true` — выпускает сертификаты Let’s Encrypt и перезапускает `nginx`

---

## 4) Настройка режимов

### 4.1 Local (быстрый тест)

`.env` минимум:
```env
DEPLOY_MODE=local

FRONT_PUBLIC_PORT=8080
KEYCLOAK_PUBLIC_PORT=8082
CAMUNDA_PUBLIC_PORT=8081
BACKEND_PUBLIC_PORT=8099
```

Запуск:
```bash
cp .env.example .env
nano .env
./install.sh
```

Проверка:
```bash
docker compose ps
```

---

### 4.2 Edge (VM/облако с DNS)

#### 4.2.1 DNS (обязательные записи)
⚠️ UniBPM и Keycloak **обязательно** должны иметь публичный адрес (subdomain или path).

**Вариант A — subdomain (рекомендуется):**
- `UNIBPM_DOMAIN` (например `ui.example.com`) → IP VM
- `KEYCLOAK_DOMAIN` (например `keycloak.example.com`) → IP VM
- опционально `CAMUNDA_DOMAIN` (например `camunda.example.com`) → IP VM (`EXPOSE_CAMUNDA=true`)

**Вариант B — path (один домен):**
- `UNIBPM_DOMAIN` (например `unibpm.example.com`) → IP VM  
  Keycloak и Camunda будут доступны как:
- `${UNIBPM_DOMAIN}${KEYCLOAK_PATH}` (например `/keycloak`)
- `${UNIBPM_DOMAIN}${CAMUNDA_PATH}` (например `/camunda`, если включено)

#### 4.2.2 Firewall / Security Group
Открыть:
- 80/tcp (всегда, если Let’s Encrypt)
- 443/tcp (если HTTPS)

#### 4.2.3 Ключевые переменные Edge
- `DEPLOY_MODE=edge`
- `EDGE_ROUTING_MODE=subdomain|path`
- `UNIBPM_DOMAIN` — домен UI (или общий домен в path)
- `KEYCLOAK_DOMAIN` — только для subdomain
- `CAMUNDA_DOMAIN` — только для subdomain (и только если `EXPOSE_CAMUNDA=true`)
- `EXPOSE_CAMUNDA=true|false`
- `ENABLE_TLS=true|false`
- `LETSENCRYPT_EMAIL` — обязателен при `ENABLE_TLS=true`
- `KEYCLOAK_PATH` (по умолчанию `/keycloak`)
- `CAMUNDA_PATH` (по умолчанию `/camunda`)

#### 4.2.4 Важно про Keycloak URL’ы
Есть два разных URL, и их нельзя путать:

- `identity.keycloak.base-url` (внутренний, для backend → Keycloak): **должен быть docker-адресом**
    - пример: `http://keycloak:8080/keycloak`
- `identity.keycloak.front-url` / `KEYCLOAK_EXTERNAL_URL` (внешний, для браузера/редиректов):
    - subdomain: `https://keycloak.example.com/keycloak`
    - path: `https://unibpm.example.com/keycloak`

Если backend пытается ходить в `http://localhost:8082/...` внутри контейнера — будут 500/Connection refused.

---

## 5) Обновление и перезапуск

### Перезапуск всего
```bash
docker compose restart
```

### Пересоздать конфиги после правки `.env`
1) Перегенерировать конфиги:
```bash
./prepare.sh
```

2) Применить:
```bash
docker compose restart unibpm camunda-bpm-7
```

3) Если меняли домены/пути/edge-настройки — перерендерить nginx (удобнее просто прогнать install.sh):
```bash
./install.sh
```

---

## 6) Troubleshooting

### DNS
```bash
dig +short ui.example.com
dig +short keycloak.example.com
```

### Порты снаружи (с другой машины)
```bash
curl -I http://ui.example.com/
curl -I http://keycloak.example.com/
```

### Логи
```bash
docker compose logs -f nginx
docker compose logs -f keycloak
docker compose logs -f unibpm
docker compose logs -f camunda-bpm-7
```

