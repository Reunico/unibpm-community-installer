# UniBPM Community Installer

Этот репозиторий — “всё включено” дистрибутив UniBPM Community, который поднимает полный стенд в Docker Compose.

Почему так: один состав сервисов = проще поддержка, диагностика и воспроизводимость окружения.

## Состав стенда

- PostgreSQL
- Kafka
- Keycloak
- UniBPM backend
- UniBPM frontend
- Camunda 7 (движок)
- Nginx (edge/gateway для доменов и HTTPS)
- Certbot (только если включён TLS)

---

## Два режима запуска

### 1) Local (для проверки на ноутбуке/локально или на VM без доменов)
Доступ по `localhost:<port>`.

### 2) Edge (для VM/облака с DNS)
Доступ по доменам, опционально TLS (Let’s Encrypt).

> В Edge **UniBPM и Keycloak обязаны** иметь внешний адрес (иначе не будет корректных OAuth2-редиректов).
> Camunda можно не публиковать наружу.

---

## Быстрый старт

### 0) Пререквизиты
- Docker Engine 20+
- Docker Compose v2 (`docker compose version`)

### 1) Скачать дистрибутив и подготовить `.env`
```bash
git clone https://github.com/Reunico/unibpm-community-installer.git
cd unibpm-community-installer

cp .env.example .env
nano .env
```

### 2) Запуск
```bash
chmod +x install.sh prepare.sh
./install.sh
```

---

## Режим A — Local (рекомендуется для первичной проверки)

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

### Полезные команды
```bash
docker compose ps
docker compose logs -f unibpm
docker compose logs -f keycloak
docker compose logs -f unibpm-engine
```

---

## Режим B — Edge (VM/облако с DNS)

В Edge есть два способа публикации:

### Вариант 1 — subdomain (рекомендуется)
Отдельные домены:
- UI: `https://<UNIBPM_DOMAIN>/`
- Keycloak: `https://<KEYCLOAK_DOMAIN>/keycloak/`
- Camunda (опционально): `https://<CAMUNDA_DOMAIN>/`

### Вариант 2 — path (всё на одном домене)
Один домен:
- UI: `https://<UNIBPM_DOMAIN>/`
- Keycloak: `https://<UNIBPM_DOMAIN>/keycloak/`
- Camunda (опционально): `https://<UNIBPM_DOMAIN>/camunda/`

> В path-режиме важно, чтобы `KEYCLOAK_PATH` и `CAMUNDA_PATH` начинались с `/`.

---

### Что нужно заранее (Edge)
1) Публичный IP у VM
2) Открытые порты (Security Group / Firewall):
   - `80/tcp` (обязательно для Let’s Encrypt HTTP-01)
   - `443/tcp` (если включаете TLS)
3) DNS A-записи на IP VM:
   - `UNIBPM_DOMAIN` → IP VM (обязательно)
   - `KEYCLOAK_DOMAIN` → IP VM (обязательно в режиме subdomain)
   - `CAMUNDA_DOMAIN` → IP VM (только если `EXPOSE_CAMUNDA=true`)

---

### Пример `.env` для Edge (subdomain + TLS)
```env
DEPLOY_MODE=edge

# ВАЖНО: installer использует EDGE_ROUTING_MODE (а не ROUTING_MODE).
EDGE_ROUTING_MODE=subdomain

UNIBPM_DOMAIN=unibpm.example.com
KEYCLOAK_DOMAIN=auth.example.com

# Camunda наружу?
EXPOSE_CAMUNDA=false
CAMUNDA_DOMAIN=camunda.example.com

# Пути публикации
KEYCLOAK_PATH=/keycloak
CAMUNDA_PATH=/camunda

# TLS (Let’s Encrypt)
ENABLE_TLS=true
LETSENCRYPT_EMAIL=admin@example.com

NGINX_HTTP_PORT=80
NGINX_HTTPS_PORT=443
```

### Запуск Edge
```bash
./install.sh
```

### URL после установки (Edge)
- UniBPM:
  - `https://<UNIBPM_DOMAIN>/` (если `ENABLE_TLS=true`)
  - `http://<UNIBPM_DOMAIN>/` (если `ENABLE_TLS=false`)
- Keycloak:
  - subdomain: `https://<KEYCLOAK_DOMAIN>/keycloak/`
  - path: `https://<UNIBPM_DOMAIN>/keycloak/`
- Camunda:
  - если `EXPOSE_CAMUNDA=true`:
    - subdomain: `https://<CAMUNDA_DOMAIN>/`
    - path: `https://<UNIBPM_DOMAIN>/camunda/`
  - если `EXPOSE_CAMUNDA=false`: Camunda доступна только внутри docker-сети (для доступа используйте SSH-туннель/проброс портов при необходимости)

---

## Частые проверки и диагностика

### Статус контейнеров
```bash
docker compose ps
```

### Логи
```bash
docker compose logs -f nginx
docker compose logs -f keycloak
docker compose logs -f unibpm
docker compose logs -f unibpm-engine
```

### Проверка DNS (с вашей машины или с VM)
```bash
dig +short <UNIBPM_DOMAIN>
dig +short <KEYCLOAK_DOMAIN>
```

### Проверка доступности снаружи (важно для Let’s Encrypt)
```bash
curl -I http://<UNIBPM_DOMAIN>/
curl -I http://<KEYCLOAK_DOMAIN>/
```

---

## Ошибка Keycloak: “Invalid parameter: redirect_uri”

Это означает, что **в Keycloak client настроены redirectUris, которые не совпадают** с реальным URL входа (домен/путь/схема).

Что проверить:
1) Откройте админку Keycloak → Realm `unibpm`
2) Clients:
   - `unibpm-front` (UI)
   - `camunda-identity-service` (Camunda SSO)
3) Убедитесь, что в **Redirect URIs** есть нужные шаблоны:

### Для UI (`unibpm-front`)
- Edge: `https://<UNIBPM_DOMAIN>/*` (или `http://.../*` если без TLS)
- Local: `http://localhost:<FRONT_PUBLIC_PORT>/*`

### Для Camunda (`camunda-identity-service`) — если публикуете Camunda наружу
- Edge subdomain:
  - `https://<CAMUNDA_DOMAIN>/*`
  - `https://<CAMUNDA_DOMAIN>/login/oauth2/code/keycloak`
  - `https://<CAMUNDA_DOMAIN>/camunda/login/oauth2/code/keycloak` (если у вас camunda под path)
- Edge path:
  - `https://<UNIBPM_DOMAIN>/camunda/*`
  - `https://<UNIBPM_DOMAIN>/login/oauth2/code/keycloak`
  - `https://<UNIBPM_DOMAIN>/camunda/login/oauth2/code/keycloak`

Если редиректы не совпадают — Keycloak вернёт `Invalid parameter: redirect_uri`.

> Installer пытается обновлять redirectUris автоматически, но если у вас менялись домены/пути/схемы — проще всего:
> 1) исправить `.env`
> 2) запустить `./install.sh` ещё раз
> 3) и/или вручную поправить redirectUris в Keycloak.

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

---

## Операционное руководство (подробно)
- [INSTALLER_INSTRUCTION.md](INSTALLER_INSTRUCTION.md)
