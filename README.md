# UniBPM Community Installer

Этот репозиторий — “всё включено” дистрибутив UniBPM Community, который поднимает полный стенд в Docker Compose.

## Что входит в стенд

- PostgreSQL (включая БД для Keycloak)
- Kafka
- Keycloak
- UniBPM backend (`unibpm`)
- UniBPM frontend (`unibpm-frontend`)
- UniBPM Engine / Camunda 7 (`unibpm-engine`)
- Nginx gateway для доменов/HTTPS (в режиме Edge)
- Certbot для Let’s Encrypt (только если включён TLS)

---

## Пререквизиты

### Обязательно
- Docker Engine 20+
- Docker Compose v2 (`docker compose version`)

### Для Edge + TLS (Let’s Encrypt)
- Публичный IP VM
- Открыты порты:
  - `80/tcp` (обязательно для Let’s Encrypt HTTP-01)
  - `443/tcp` (для HTTPS)
- DNS A-записи на IP VM (см. ниже)

---

## Два режима запуска

1) **Local** — доступ по портам `localhost`  
2) **Edge** — доступ по доменам и (опционально) TLS через Let’s Encrypt

> В Edge **UniBPM и Keycloak обязаны** иметь внешний URL (иначе OAuth2-редиректы не совпадут).  
> Camunda можно **не** публиковать наружу.

---

## Быстрый старт

```bash
git clone https://github.com/Reunico/unibpm-community-installer.git
cd unibpm-community-installer

cp .env.example .env
nano .env

chmod +x install.sh prepare.sh
./install.sh
```

Проверка:
```bash
docker compose ps
docker compose logs -f unibpm
docker compose logs -f keycloak
docker compose logs -f unibpm-engine
```

---

## Режим A — Local

### Минимальные настройки `.env`
```env
DEPLOY_MODE=local

FRONT_PUBLIC_PORT=8080
BACKEND_PUBLIC_PORT=8099
KEYCLOAK_PUBLIC_PORT=8082
CAMUNDA_PUBLIC_PORT=8081
```

### URL после установки
- UniBPM UI: `http://localhost:8080/`
- Keycloak: `http://localhost:8082/keycloak/`
- Camunda (webapp): `http://localhost:8081/`

---

## Режим B — Edge (VM/облако с DNS)

### 1) Схемы публикации: subdomain vs path

В Edge поддерживаются две схемы роутинга — задаются переменной `EDGE_ROUTING_MODE`.

#### Вариант 1 — subdomain (рекомендуется)
Отдельные домены:
- UI: `https://<UNIBPM_DOMAIN>/`
- Keycloak: `https://<KEYCLOAK_DOMAIN><KEYCLOAK_PATH>/` (обычно `/keycloak`)
- Camunda (опционально): `https://<CAMUNDA_DOMAIN>/` (только если `EXPOSE_CAMUNDA=true`)

#### Вариант 2 — path (всё на одном домене)
Один домен:
- UI: `https://<UNIBPM_DOMAIN>/`
- Keycloak: `https://<UNIBPM_DOMAIN><KEYCLOAK_PATH>/`
- Camunda (опционально): `https://<UNIBPM_DOMAIN><CAMUNDA_PATH>/`

> В обоих вариантах `KEYCLOAK_PATH` и `CAMUNDA_PATH` должны начинаться с `/`.

---

### 2) DNS (обязательно)

**Subdomain:**
- `UNIBPM_DOMAIN` → IP VM
- `KEYCLOAK_DOMAIN` → IP VM
- `CAMUNDA_DOMAIN` → IP VM (только если `EXPOSE_CAMUNDA=true`)

**Path:**
- `UNIBPM_DOMAIN` → IP VM

Проверка DNS:
```bash
dig +short <UNIBPM_DOMAIN>
dig +short <KEYCLOAK_DOMAIN>
```

---

### 3) Firewall / Security Group

Открыть:
- `80/tcp` (всегда, если Let’s Encrypt)
- `443/tcp` (если HTTPS)

Быстрая проверка (важно для Let’s Encrypt):
```bash
curl -I http://<UNIBPM_DOMAIN>/
curl -I http://<KEYCLOAK_DOMAIN>/
```

---

### 4) Пример `.env` для Edge (subdomain + TLS)

```env
DEPLOY_MODE=edge

# subdomain | path
EDGE_ROUTING_MODE=subdomain

UNIBPM_DOMAIN=unibpm.example.com
KEYCLOAK_DOMAIN=auth.example.com

# Camunda наружу по DNS? (опционально)
EXPOSE_CAMUNDA=false
CAMUNDA_DOMAIN=camunda.example.com

# Публичные пути
KEYCLOAK_PATH=/keycloak
CAMUNDA_PATH=/camunda

# TLS (Let’s Encrypt HTTP-01)
ENABLE_TLS=true
LETSENCRYPT_EMAIL=admin@example.com

NGINX_HTTP_PORT=80
NGINX_HTTPS_PORT=443

# Доп. origins для WebSocket/CORS (через запятую)
EXTRA_ALLOWED_ORIGINS=
```

Запуск:
```bash
./install.sh
```

URL после установки:
- UniBPM: `https://<UNIBPM_DOMAIN>/` (или `http://...` если `ENABLE_TLS=false`)
- Keycloak:
  - subdomain: `https://<KEYCLOAK_DOMAIN>/keycloak/`
  - path: `https://<UNIBPM_DOMAIN>/keycloak/`
- Camunda:
  - если `EXPOSE_CAMUNDA=true`:
    - subdomain: `https://<CAMUNDA_DOMAIN>/`
    - path: `https://<UNIBPM_DOMAIN>/camunda/`
  - если `EXPOSE_CAMUNDA=false`: работает внутри docker-сети; для доступа используйте порт `CAMUNDA_PUBLIC_PORT` (если он открыт) или SSH-туннель/проброс портов

> Примечание по безопасности: backend по умолчанию публикуется на `BACKEND_PUBLIC_PORT` (8099).  
> В Edge обычно закрывайте этот порт на firewall, если он не нужен снаружи.

---

## Как работает installer (коротко)

Главная команда — `install.sh`. Его можно запускать повторно: данные в volume не удаляются.

Последовательность:
1) Загружает `.env`
2) Вычисляет и экспортирует:
   - `PUBLIC_SCHEME` (http/https)
   - `KEYCLOAK_EXTERNAL_URL` (внешний URL Keycloak для браузера/редиректов)
3) Генерирует `generated/nginx/default.conf` из шаблонов `nginx/conf/*.tpl` (в зависимости от режима)
4) Поднимает инфраструктуру: `postgres`, `kafka`, `keycloak`
5) Запускает `prepare.sh`, который:
   - ждёт готовность Keycloak
   - получает admin token
   - вытаскивает client secrets
   - генерирует:
     - `generated/unibpm/application.yaml`
     - `generated/engine/application.yaml`
   - (опционально) обновляет redirect/web origins клиентов в Keycloak (зависит от режима и флагов)
6) Поднимает `unibpm`, `unibpm-engine`, `unibpm-frontend`
7) В Edge поднимает `nginx`
8) В Edge + TLS выпускает сертификаты Let’s Encrypt и перезапускает `nginx`

---

## Важно про URL Keycloak: внутренний vs внешний

Есть два принципиально разных URL:

- **Внутренний** (backend → Keycloak): должен быть docker-адресом, например `http://keycloak:8080/keycloak`
- **Внешний** (браузер/редиректы): это `KEYCLOAK_EXTERNAL_URL`, например:
  - subdomain: `https://auth.example.com/keycloak`
  - path: `https://unibpm.example.com/keycloak`
  - local: `http://localhost:8082/keycloak`

Если backend внутри контейнера пытается ходить в `http://localhost:8082/...` — получите `Connection refused`.

---

## WebSocket (/stomp), CORS и встраивание UI

UniBPM использует WebSocket endpoint (по умолчанию `/stomp`).  
Чтобы не ловить ошибки в браузере (включая Safari) и при работе через DNS/TLS/iframe, в `ws.allowed-origins` должны попадать:
- `http://localhost:3001` (dev)
- `http://localhost:<BACKEND_PUBLIC_PORT>` (локальный backend)
- `https://<UNIBPM_DOMAIN>` (edge)
- любые дополнительные порталы/домены, если UI встраивается или проксируется

Installer генерирует origins из `.env`, дополнительные значения задайте через `EXTRA_ALLOWED_ORIGINS`.

---

## Частые проблемы

### 1) Let’s Encrypt не выпускает сертификат
Проверьте:
- домены реально резолвятся на IP VM (`dig +short ...`)
- порт **80** открыт снаружи
- на порту 80 нет другого сервиса (Apache/старый nginx)

Проверка:
```bash
curl -I http://<UNIBPM_DOMAIN>/
curl -I http://<KEYCLOAK_DOMAIN>/
docker compose logs -f nginx
```

---

### 2) Ошибка Keycloak: `Invalid parameter: redirect_uri`
Это означает, что **в Keycloak client настроены redirectUris, которые не совпадают** с реальным URL входа (домен/путь/схема).

Где править:
- Keycloak Admin Console → Realm `unibpm`
- Clients:
  - `unibpm-front` (UI)
  - `camunda-identity-service` (Camunda SSO, если публикуете Camunda наружу)

Что должно быть в **Redirect URIs**:

**UI (`unibpm-front`)**
- Edge: `https://<UNIBPM_DOMAIN>/*` (или `http://.../*` без TLS)
- Local: `http://localhost:<FRONT_PUBLIC_PORT>/*`

**Camunda (`camunda-identity-service`) — только если `EXPOSE_CAMUNDA=true`**
- Local:
  - `http://localhost:<CAMUNDA_PUBLIC_PORT>/*`
  - `http://localhost:<CAMUNDA_PUBLIC_PORT>/login/oauth2/code/keycloak`
- Edge subdomain:
  - `https://<CAMUNDA_DOMAIN>/*`
  - `https://<CAMUNDA_DOMAIN>/login/oauth2/code/keycloak`
  - `https://<CAMUNDA_DOMAIN><CAMUNDA_PATH>/login/oauth2/code/keycloak` (если используете path-структуру внутри приложения)
- Edge path:
  - `https://<UNIBPM_DOMAIN><CAMUNDA_PATH>/*`
  - `https://<UNIBPM_DOMAIN>/login/oauth2/code/keycloak`
  - `https://<UNIBPM_DOMAIN><CAMUNDA_PATH>/login/oauth2/code/keycloak`

Если вы меняли домен/путь/схему http→https — обновите `.env` и прогоните:
```bash
./install.sh
```

---

## Обновление и перезапуск

Перезапуск всего:
```bash
docker compose restart
```

Пересоздать конфиги после правки `.env`:
```bash
./prepare.sh
docker compose restart unibpm unibpm-engine
```

Если меняли домены/пути/edge-настройки — удобнее прогнать полный сценарий:
```bash
./install.sh
```

---

## Остановка/удаление

Остановить:
```bash
docker compose down
```

Остановить и удалить volume Postgres (⚠️ удалит данные):
```bash
docker compose down -v
```
