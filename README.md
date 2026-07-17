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

- Linux-сервер с архитектурой `x86_64` или `arm64`, поддерживаемой используемыми Docker-образами
- Docker Engine 20+
- Docker Compose v2
- Не менее 4 vCPU
- Не менее 8 GiB RAM
- Не менее 40 GiB свободного места на SSD
- Доступ к container registry для загрузки Docker-образов

Проверка Docker Compose:

```bash
docker compose version
```

> 4 vCPU, 8 GiB RAM и 40 GiB SSD — стартовый минимум для ознакомления, демонстрации и функционального тестирования.
>
> Installer запускает на одном сервере UniBPM, Process Engine, PostgreSQL, Kafka и Keycloak. При оценке ресурсов необходимо учитывать их суммарное потребление.
>
> Фактические требования зависят от количества зарегистрированных и одновременно активных пользователей, запускаемых процессов, пользовательских задач, API-запросов, интеграций, вложений и срока хранения данных.
>
> Для Pilot и Production используйте раздел документации [«Системные требования и сайзинг»](https://unibpm.ru/docs/user-guide/system-requirements-and-sizing/) и подтверждайте выбранную конфигурацию нагрузочным тестированием.

### Требования к диску

Рекомендуется использовать SSD.

Дисковое пространство требуется для:

- Docker-образов и файлов приложения
- баз данных PostgreSQL
- истории выполнения процессов
- пользовательских вложений
- данных Kafka
- журналов контейнеров
- резервных копий, если они хранятся на том же сервере

40 GiB достаточно только для небольшого тестового стенда без большого количества вложений, продолжительного хранения истории и локального хранения резервных копий.

Для Pilot и Production необходимо предусмотреть запас свободного места и возможность расширения диска.

### Внешние платформенные сервисы

По умолчанию installer поднимает собственные PostgreSQL, Kafka и Keycloak.

При использовании внешних PostgreSQL, Kafka или Identity Provider ресурсы этих компонентов не входят в требования к серверу UniBPM и рассчитываются отдельно.

Также необходимо учитывать:

- сетевую задержку между компонентами
- пропускную способность сети
- доступность внешних сервисов
- объём и срок хранения данных
- резервное копирование и восстановление

### Для Edge + TLS (Let’s Encrypt)
- Публичный IP VM
- Открытый порт `80/tcp` для Let’s Encrypt HTTP-01
- Открытый порт `443/tcp` для HTTPS
- DNS A-записи, направленные на публичный IP VM
- Исходящий доступ к серверам Let’s Encrypt

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

#### Данные для входа
```
login=admin
password=admin
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

В стенде одновременно используются **несколько разных URL Keycloak**, и их нельзя путать:

1) **KEYCLOAK_BASE_URL (internal)** — как к Keycloak обращаются контейнеры внутри docker-сети.
    - edge + subdomain: `https://auth.example.com/keycloak`
    - edge + path: `https://unibpm.example.com/keycloak`
    - local: `http://keycloak:8080/keycloak`

2) **KEYCLOAK_INTERNAL_URL (host)** — как к Keycloak обращается *prepare.sh*, который выполняется на хосте.
   Обычно это опубликованный порт: `http://localhost:8082/keycloak`.

3) **KEYCLOAK_EXTERNAL_URL (public/frontchannel)** — как Keycloak видит браузер и куда должны попадать OAuth2 redirect_uri.
   Это значение **вычисляет `install.sh`** (по `DEPLOY_MODE`, `EDGE_ROUTING_MODE`, `ENABLE_TLS`, доменам и путям), например:
   - edge + subdomain: `https://auth.example.com/keycloak`
   - edge + path: `https://unibpm.example.com/keycloak`
   - local: `http://localhost:8082/keycloak`

Почему это важно:
- если контейнер (`unibpm`/`unibpm-engine`) пытается ходить в `http://localhost:8082/...` → будет `Connection refused`;
- если браузер редиректится на internal URL (`http://keycloak:8080/...`) → OAuth2 ломается;
- если **issuer** (значение `iss` в токене) не совпадает с `issuer-uri` в приложениях → приложения начнут отклонять JWT.

Официально: в Keycloak можно (и часто нужно) отдельно задавать публичный URL (frontend) и внутренний/backchannel, особенно за reverse-proxy. citeturn0search2turn0search0

### Что куда используется в этом дистрибутиве

**UniBPM (`unibpm`)** генерируемый `generated/unibpm/application.yaml` использует:
- `spring.security.oauth2.resourceserver.jwt.issuer-uri` → **KEYCLOAK_EXTERNAL_URL** (проверка `iss`),
- `...jwk-set-uri` и `...token-uri` → **KEYCLOAK_BASE_URL** (получение ключей/токенов по внутреннему адресу).

**Engine (`unibpm-engine`)** генерируемый `generated/engine/application.yaml` использует:
- `authorization-uri` → **KEYCLOAK_EXTERNAL_URL** (браузерный вход),
- `token-uri`/`jwk-set-uri` → **KEYCLOAK_BASE_URL** (внутренние вызовы),
- `redirect-uri` строится из `CAMUNDA_BASE_URL`.

Это нормальная и распространённая схема: *frontchannel* идёт через публичный URL, *backchannel* — по внутреннему адресу. citeturn0search2turn0search0

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

## Как правильно перегенерировать конфиги (и почему `prepare.sh` нельзя запускать «как есть»)

`prepare.sh` ожидает, что переменная **KEYCLOAK_EXTERNAL_URL** уже вычислена (это делает `install.sh`).

Правильный порядок после изменения `.env`:

1) Если вы меняли домены/пути/режим/HTTPS → запускайте полный сценарий:
```bash
./install.sh
```

2) Если вы меняли только прикладные параметры (например, CORS/WS origins) и **не** трогали домены/пути/режим:
```bash
./install.sh
# либо (альтернатива) экспортировать KEYCLOAK_EXTERNAL_URL вручную и запускать prepare.sh,
# но это для опытных пользователей.
```

### Рекомендация по стабильному issuer за reverse proxy

Чтобы Keycloak всегда выдавал токены с ожидаемым `iss` (и не зависел от того, кто и по какому адресу к нему обратился),
в edge-режиме рекомендуется задать hostname/URL Keycloak (например, через `KC_HOSTNAME`/`hostname` настройки).
Это особенно важно при `EDGE_ROUTING_MODE=path` и при публикации через nginx.

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
