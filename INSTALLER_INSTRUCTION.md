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

Дистрибутив всегда запускает:
- `postgres` (данные UniBPM и Keycloak)
- `kafka`
- `keycloak` (realm + clients импортируются из `keycloak/config`)
- `unibpm` (backend)
- `unibpm-frontend` (frontend + свой nginx внутри контейнера)
- `camunda-bpm-7`
- `nginx` (внешний gateway для edge/DNS/HTTPS)
- `certbot` (выпуск/обновление сертификатов Let’s Encrypt)

---

## 3) Порядок запуска (как работает installer)

Запуск выполняет `install.sh`:

### install.sh можно запускать повторно - существующие volume и данные не удаляются.

1) Загружает `.env`
2) Вычисляет и экспортирует:
   - `PUBLIC_SCHEME` (http/https)
   - `KEYCLOAK_EXTERNAL_URL` (URL для браузера/редиректов)
3) Генерирует `generated/nginx/default.conf` из шаблонов `nginx/conf/*.tpl`
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

#### DNS

####  ⚠️ UniBPM и Keycloak ОБЯЗАТЕЛЬНО на DNS

Минимальный набор доменов:
- `UNIBPM_DOMAIN` (например `unibpm.example.com`) → IP VM
- `KEYCLOAK_DOMAIN` (например `auth.example.com`) → IP VM

Опционально Camunda:
- `CAMUNDA_DOMAIN` (например `camunda.example.com`) → IP VM
- включить публикацию: `EXPOSE_CAMUNDA=true`

#### Firewall / Security Group
Открыть:
- 80/tcp (всегда, если Let’s Encrypt)
- 443/tcp (если HTTPS)

#### `.env` (пример edge+tls)
```env
DEPLOY_MODE=edge

UNIBPM_DOMAIN=unibpm.example.com
KEYCLOAK_DOMAIN=auth.example.com

EXPOSE_CAMUNDA=false
CAMUNDA_DOMAIN=camunda.example.com

ENABLE_TLS=true
LETSENCRYPT_EMAIL=admin@example.com

NGINX_HTTP_PORT=80
NGINX_HTTPS_PORT=443
```

Запуск:
```bash
./install.sh
```

---

## 5) Обновление и перезапуск


### Перезапуск
```bash
docker compose restart
```

### Пересоздать конфиги (например, после правки `.env`)
```bash
./prepare.sh
docker compose restart unibpm camunda-bpm-7 nginx
```

---

## 6) Troubleshooting

### DNS
```bash
dig +short unibpm.example.com
dig +short auth.example.com
```

### Порты снаружи
С другой машины:
```bash
curl -I http://unibpm.example.com/
curl -I http://auth.example.com/
```

### Логи TLS/сертификатов
```bash
docker compose logs -f nginx
docker compose logs certbot
```

### Keycloak / prepare.sh
```bash
docker compose logs -f keycloak
```

