# UniBPM Community — Installer Instruction (операционное руководство)

Документ для инженеров, которые разворачивают UniBPM Community локально или на VM/в облаке.

---

## 1) Пререквизиты

### Обязательное
- Docker Engine 20+
- Docker Compose v2 (`docker compose version`)
- Доступ к registry (если образы приватные)

### Для Edge + TLS (Let’s Encrypt)
- Публичный IP VM
- Открыты порты:
  - `80/tcp` (обязательно для Let’s Encrypt HTTP-01)
  - `443/tcp` (для HTTPS)
- DNS A-записи на IP VM (см. раздел 4)

---

## 2) Что поднимается в стенде

Дистрибутив запускает полный набор сервисов:

- `postgres`
- `kafka`
- `keycloak`
- `unibpm` (backend)
- `unibpm-engine` (Camunda/engine REST)
- `unibpm-frontend` (frontend)
- `nginx` (edge/gateway)
- `certbot` (только при `ENABLE_TLS=true`)

---

## 3) Как устроен запуск

### Главная команда
Запуск выполняет `install.sh`.

> `install.sh` можно запускать повторно. Данные в volume не удаляются.

### Последовательность действий
1) Загружает `.env`
2) Вычисляет “публичные” URL (схема http/https, внешний URL Keycloak для браузера)
3) В Edge рендерит nginx конфиг в `generated/nginx/default.conf` из шаблонов
4) Поднимает инфраструктуру: `postgres`, `kafka`, `keycloak`
5) Запускает `prepare.sh`, который:
   - ждёт готовность realm в Keycloak
   - получает admin token
   - читает client secrets из Keycloak
   - генерирует конфиги:
     - `generated/unibpm/application.yaml`
     - `generated/engine/application.yaml`
   - (опционально) обновляет `redirectUris/webOrigins` клиентов в Keycloak (в зависимости от режима)
6) Поднимает `unibpm`, `unibpm-engine`, `unibpm-frontend`
7) В Edge поднимает `nginx` (HTTP)
8) Если `ENABLE_TLS=true`:
   - выпускает сертификат Let’s Encrypt (webroot)
   - перерисовывает nginx под TLS
   - перезапускает nginx

---

## 4) Конфигурация режимов

### 4.1 Local (быстрый тест)

Минимально в `.env`:
```env
DEPLOY_MODE=local

FRONT_PUBLIC_PORT=8080
KEYCLOAK_PUBLIC_PORT=8082
CAMUNDA_PUBLIC_PORT=8081
```

Запуск:
```bash
cp .env.example .env
nano .env
chmod +x install.sh prepare.sh
./install.sh
```

Проверка:
```bash
docker compose ps
```

---

### 4.2 Edge (VM/облако с DNS)

#### 4.2.1 Роутинг в Edge: subdomain vs path

**subdomain (рекомендуется)** — разные домены:
- `UNIBPM_DOMAIN` → UI
- `KEYCLOAK_DOMAIN` → Keycloak
- `CAMUNDA_DOMAIN` → Camunda (опционально, если `EXPOSE_CAMUNDA=true`)

**path** — один домен, всё через пути:
- домен: `UNIBPM_DOMAIN`
- Keycloak: `UNIBPM_DOMAIN + KEYCLOAK_PATH`
- Camunda: `UNIBPM_DOMAIN + CAMUNDA_PATH` (если включено)

#### 4.2.2 DNS (обязательно)
**Вариант A — subdomain:**
- `UNIBPM_DOMAIN` → IP VM
- `KEYCLOAK_DOMAIN` → IP VM
- `CAMUNDA_DOMAIN` → IP VM (только если `EXPOSE_CAMUNDA=true`)

**Вариант B — path:**
- `UNIBPM_DOMAIN` → IP VM

#### 4.2.3 Firewall / Security Group
Открыть:
- `80/tcp` (всегда, если используете Let’s Encrypt)
- `443/tcp` (если включаете TLS)

#### 4.2.4 Ключевые переменные Edge

**Важно про имена переменных:**
- В скриптах используется `EDGE_ROUTING_MODE` (а не `ROUTING_MODE`).
- Если у вас в `.env` есть `ROUTING_MODE`, он не будет влиять на выбор схемы. Используйте `EDGE_ROUTING_MODE`.

Список:
- `DEPLOY_MODE=edge`
- `EDGE_ROUTING_MODE=subdomain|path`
- `UNIBPM_DOMAIN`
- `KEYCLOAK_DOMAIN` (только subdomain)
- `CAMUNDA_DOMAIN` (только subdomain, и только если `EXPOSE_CAMUNDA=true`)
- `EXPOSE_CAMUNDA=true|false`
- `KEYCLOAK_PATH` (обычно `/keycloak`)
- `CAMUNDA_PATH` (обычно `/camunda`)
- `ENABLE_TLS=true|false`
- `LETSENCRYPT_EMAIL` (обязательно если `ENABLE_TLS=true`)

Пример Edge subdomain + TLS:
```env
DEPLOY_MODE=edge
EDGE_ROUTING_MODE=subdomain

UNIBPM_DOMAIN=unibpm.example.com
KEYCLOAK_DOMAIN=auth.example.com

EXPOSE_CAMUNDA=false
CAMUNDA_DOMAIN=camunda.example.com

KEYCLOAK_PATH=/keycloak
CAMUNDA_PATH=/camunda

ENABLE_TLS=true
LETSENCRYPT_EMAIL=admin@example.com
NGINX_HTTP_PORT=80
NGINX_HTTPS_PORT=443
```

---

## 5) Перегенерация конфигов и перезапуск

### Быстрый перезапуск контейнеров
```bash
docker compose restart
```

### Если изменили `.env` и нужно пересобрать конфиги приложения
1) Перегенерировать:
```bash
./prepare.sh
```

2) Применить:
```bash
docker compose restart unibpm unibpm-engine
```

### Если изменили домены/пути/edge-настройки nginx
Самый простой путь — прогнать полный сценарий:
```bash
./install.sh
```

---

## 6) Диагностика

### Проверка DNS
```bash
dig +short <UNIBPM_DOMAIN>
dig +short <KEYCLOAK_DOMAIN>
```

### Проверка портов снаружи (важно для Let’s Encrypt)
```bash
curl -I http://<UNIBPM_DOMAIN>/
curl -I http://<KEYCLOAK_DOMAIN>/
```

### Логи
```bash
docker compose logs -f nginx
docker compose logs -f keycloak
docker compose logs -f unibpm
docker compose logs -f unibpm-engine
```

---

## 7) Типовая проблема: Keycloak “Invalid parameter: redirect_uri”

Причина: вход в OAuth2 возвращается на URL, который **не разрешён** в настройках Keycloak клиента.

Где править:
- Keycloak Admin Console → Realm `unibpm`
- Clients:
  - `unibpm-front` (UI)
  - `camunda-identity-service` (Camunda SSO)

Что должно быть в Redirect URIs:

### UI (`unibpm-front`)
- Edge: `https://<UNIBPM_DOMAIN>/*` (или `http://.../*` без TLS)
- Local: `http://localhost:<FRONT_PUBLIC_PORT>/*`

### Camunda (`camunda-identity-service`) — только если `EXPOSE_CAMUNDA=true`
**Edge subdomain:**
- `https://<CAMUNDA_DOMAIN>/*`
- `https://<CAMUNDA_DOMAIN>/login/oauth2/code/keycloak`
- `https://<CAMUNDA_DOMAIN>/camunda/login/oauth2/code/keycloak` (если camunda под path)

**Edge path:**
- `https://<UNIBPM_DOMAIN>/camunda/*`
- `https://<UNIBPM_DOMAIN>/login/oauth2/code/keycloak`
- `https://<UNIBPM_DOMAIN>/camunda/login/oauth2/code/keycloak`

Если вы сменили домен/схему http→https/путь — обновите `.env` и запустите:
```bash
./install.sh
```

---

## 8) Остановка и удаление

Остановить:
```bash
docker compose down
```

Удалить вместе с данными Postgres (⚠️ удалит данные):
```bash
docker compose down -v
```
