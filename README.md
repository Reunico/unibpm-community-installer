# UniBPM Community — Getting Started

**Community-дистрибутив содержит все компоненты решения и запускается “всё включено”.**
Это осознанное решение: так проще поддержка, диагностика и воспроизводимость окружения у клиентов.

- PostgreSQL
- Kafka
- Keycloak
- UniBPM backend
- UniBPM frontend
- Camunda 7
- Nginx (gateway для DNS/HTTPS)

Поддерживаются 2 режима запуска:

1) **Local (для теста на ноутбуке/локально)** — доступ по портам `localhost`
2) **Edge (для VM/облака с DNS)** — доступ по доменам (**UniBPM + Keycloak обязательно**, **Camunda по желанию**) и опционально TLS через Let’s Encrypt

---

## Быстрый старт

### 1) Скачать и развернуть дистрибутив

```bash
git clone https://github.com/Reunico/unibpm-community-installer.git
cd unibpm-community-installer

cp .env.example .env
nano .env

chmod +x install.sh prepare.sh
./install.sh
```

---

## Режим A — Local (рекомендуется для первичной проверки)

### Настройки `.env`

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
- Camunda: `http://localhost:8081/`

### Проверка состояния
```bash
docker compose ps
docker compose logs -f unibpm
docker compose logs -f keycloak
```

---

## Режим B — Edge (VM/облако с DNS)

---

## Edge: варианты роутинга (subdomain vs path)

В режиме **Edge** поддерживаются **2 схемы публикации**:

### 1) Subdomain
Отдельные домены:
- UI: `https://<UNIBPM_DOMAIN>/`
- Keycloak: `https://<KEYCLOAK_DOMAIN><KEYCLOAK_PATH>/` (обычно `/keycloak`)
- Camunda (опционально): `https://<CAMUNDA_DOMAIN>/`

Подходит, когда есть возможность завести 2–3 DNS A-записи.

### 2) Path (всё на одном домене)
Один домен:
- UI: `https://<UNIBPM_DOMAIN>/`
- Keycloak: `https://<UNIBPM_DOMAIN><KEYCLOAK_PATH>/`
- Camunda (опционально): `https://<UNIBPM_DOMAIN><CAMUNDA_PATH>/`

Подходит, когда можно завести только 1 DNS A-запись.

> В обоих вариантах `KEYCLOAK_PATH` и `CAMUNDA_PATH` должны начинаться с `/`.


### Что нужно заранее
1) **Публичный IP** у VM
2) Открытые порты (Security Group / Firewall):
    - `80/tcp` (обязательно для Let’s Encrypt HTTP-01)
    - `443/tcp` (если включаете TLS)
3) DNS A-записи на IP VM:
    - `UNIBPM_DOMAIN` → IP VM (**обязательно**)
    - `KEYCLOAK_DOMAIN` → IP VM (**обязательно**)
    - `CAMUNDA_DOMAIN` → IP VM (**только если EXPOSE_CAMUNDA=true**)

### Настройки `.env` (пример)

```env
DEPLOY_MODE=edge

UNIBPM_DOMAIN=unibpm.example.com
KEYCLOAK_DOMAIN=auth.example.com

# Camunda наружу по DNS? (опционально)
EXPOSE_CAMUNDA=false
CAMUNDA_DOMAIN=camunda.example.com

# TLS (Let’s Encrypt HTTP-01)
ENABLE_TLS=true
LETSENCRYPT_EMAIL=admin@example.com

NGINX_HTTP_PORT=80
NGINX_HTTPS_PORT=443
```


### Важные переменные для Edge

```env
# Схема роутинга в Edge: subdomain | path
EDGE_ROUTING_MODE=subdomain

# Путь, по которому публикуется Keycloak (и во внешнем URL тоже)
KEYCLOAK_PATH=/keycloak

# Путь, по которому публикуется Camunda в режиме path
CAMUNDA_PATH=/camunda

# Доп. origins для WebSocket/CORS (через запятую)
# EXTRA_ALLOWED_ORIGINS=https://id.reunico.com,https://some.portal.example.com
EXTRA_ALLOWED_ORIGINS=
```


### Запуск
```bash
./install.sh
```

### URL после установки
- UniBPM: `https://unibpm.example.com/` (или `http://...` если `ENABLE_TLS=false`)
- Keycloak: `https://auth.example.com/keycloak/`
- Camunda:
    - если `EXPOSE_CAMUNDA=true` → `https://camunda.example.com/`
    - если `false` → Camunda работает внутри docker-сети; для доступа используйте порт `CAMUNDA_PUBLIC_PORT` (если он открыт) или SSH-туннель

---

## Диагностика (самые полезные команды)

### WebSocket (/stomp) и Safari/iframe.html

UniBPM использует WebSocket endpoint (по умолчанию `/stomp`).  
Чтобы не ловить ошибки в браузерах и при работе через DNS/TLS, важно чтобы в `ws.allowed-origins`
попадали:
- `http://localhost:3001` (dev)
- `http://localhost:<BACKEND_PUBLIC_PORT>` (локальный backend)
- `https://<UNIBPM_DOMAIN>` (edge)
- любые дополнительные порталы/домен(ы), если UI встраивается или проксируется

Эти значения генерируются installer-ом из переменных `.env` (см. `EXTRA_ALLOWED_ORIGINS`).



### Статус контейнеров
```bash
docker compose ps
```

### Логи
```bash
docker compose logs -f nginx
docker compose logs -f keycloak
docker compose logs -f unibpm
docker compose logs -f camunda-bpm-7
```

### Проверка DNS (с вашей машины или с VM)
```bash
dig +short unibpm.example.com
dig +short auth.example.com
```

---

## Частые проблемы и решения

### 1) Let’s Encrypt не выпускает сертификат
Проверьте:
- домены реально резолвятся на IP VM (`dig +short ...`)
- порт **80** открыт снаружи
- на порту 80 нет другого сервиса (Apache/старый nginx)

Быстрая проверка:
```bash
curl -I http://unibpm.example.com/
curl -I http://auth.example.com/
```

### 2) После включения TLS браузер не открывает сайт
Проверьте порт 443 и логи nginx:
```bash
docker compose logs -f nginx
```

### 3) Ошибки авторизации/редиректов в Keycloak
Убедитесь, что вы заходите на Keycloak по правильному домену/пути:
- `https://auth.example.com/keycloak/` (edge)
- `http://localhost:8082/keycloak/` (local)

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

- [Инструкция по установке](INSTALLER_INSTRUCTION.md)
