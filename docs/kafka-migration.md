# Миграция Kafka 2.3/ZooKeeper в Kafka 4.3.1/KRaft

Kafka 4.3 работает только в KRaft, поэтому старый ZooKeeper-based кластер нельзя обновить прямой заменой Docker-образа или повторным использованием его data-директорий. [Официальный upgrade guide Apache Kafka](https://kafka.apache.org/43/getting-started/upgrade/) требует отдельной миграции ZooKeeper-кластера в KRaft.

Инструкция ниже предназначена для случаев, когда старые сообщения или consumer offsets нужно сохранить. Конкретные адреса, TLS/SASL-параметры и список топиков необходимо адаптировать под окружение.

## Рекомендуемая схема

Перенос выполняется между двумя параллельно доступными кластерами:

- `source` — старый Kafka 2.3 + ZooKeeper;
- `target` — новый Kafka 4.3.1 в KRaft;
- migration worker — Kafka Connect/MirrorMaker 2, имеющий доступ к обоим кластерам.

Для Community/demo-инсталляций без ценных данных migration worker не нужен: сохраните backup старого стенда и разверните новый Kafka с чистым `kafka-data`.

В single-node профиле также заданы replication factor и minimum ISR для share
groups internal topic равными `1`; это необходимо для работы Kafka 4.3 на одном
брокере.

## Порядок миграции

### 1. Сохранить исходный кластер

- Запишите версии, адреса брокеров, список topics, partition count, retention, cleanup policy, ACL и consumer groups.
- Остановите изменения compose-файла до окончания миграции.
- Сохраните backup PostgreSQL и Kafka data. Для старого installer сначала определите фактические Docker mounts:

  ```bash
  docker inspect <old-kafka-container>
  ```

- Не выполняйте `docker compose down -v`, не удаляйте старый контейнер и его volume. После удаления восстановить старые сообщения и offsets штатными средствами будет нельзя.

### 2. Подготовить target

Разверните текущий compose с новым именованным volume `kafka-data` отдельно от старого проекта или на новом хосте. Убедитесь, что target работает в KRaft, имеет нужные topics/partition count и доступен migration worker.

Не монтируйте в Kafka 4.3 каталоги старого ZooKeeper-based broker, ZooKeeper data или старый Kafka log directory.

### 3. Настроить MirrorMaker 2

Рекомендуемый инструмент — MirrorMaker 2 из Kafka Connect. Минимальный пример настроек:

```properties
clusters=source,target
source.bootstrap.servers=old-kafka:29092
target.bootstrap.servers=new-kafka:29092

source->target.enabled=true
source->target.topics=^(?!__.*$).*
source->target.groups=unibpm.*|camunda.*
source->target.emit.checkpoints.enabled=true
source->target.sync.group.offsets.enabled=false

# Для single-node target внутренние MM2 topics также должны иметь RF=1.
replication.factor=1
checkpoints.topic.replication.factor=1
heartbeats.topic.replication.factor=1
offset-syncs.topic.replication.factor=1

# Используйте только если target должен сохранить исходные имена topics.
replication.policy.class=org.apache.kafka.connect.mirror.IdentityReplicationPolicy
```

По умолчанию MM2 добавляет префикс `source` к именам topics. Это безопаснее для параллельной проверки, но перед cutover потребуется сопоставить имена. `IdentityReplicationPolicy` сохраняет исходные имена, однако требует, чтобы одноимённых topics уже не было на target.

Не переносите вручную `__consumer_offsets`, `__transaction_state`, KRaft metadata или ZooKeeper data: это внутреннее состояние конкретного кластера. MM2 умеет передавать checkpoints и offsets между кластерами через свои внутренние topics ([документация MM2](https://kafka.apache.org/43/configuration/mirrormaker-configs/)).

### 4. Проверить репликацию

Дождитесь нулевого или согласованного replication lag и сравните source/target по:

- topics и partition count;
- latest offsets;
- ключам, headers и timestamp;
- retention и cleanup policy;
- ACL и параметрам producer/consumer.

Проверьте несколько сообщений каждого типа и убедитесь, что порядок внутри partition сохраняется. До переключения приложений target должен быть доступен из контейнеров `unibpm` и `unibpm-engine`.

### 5. Выполнить cutover consumers

1. Остановите или переведите в drain mode UniBPM Backend и Engine, чтобы source consumer groups перестали менять offsets.
2. Дождитесь финальных checkpoints и завершения репликации.
3. При необходимости включите `source->target.sync.group.offsets.enabled=true` на время переключения либо примените checkpoints по правилам используемой версии MM2.
4. Запустите consumers на target и проверьте, что они продолжают с ожидаемых позиций.

Возможны повторная доставка последних сообщений или необходимость идемпотентной обработки. Это нужно проверить на тестовом cutover до production-переключения.

### 6. Переключить Community Installer

Укажите bootstrap-адрес target в `.env`:

```env
KAFKA_BOOTSTRAP_SERVERS=new-kafka.example.com:9092
```

Для внешнего production-кластера настройте также требуемые TLS/SASL/ACL-параметры в конфигурации приложений. В текущем compose встроенный сервис `kafka` остаётся частью standalone-профиля, поэтому при production-запуске используйте отдельный compose override или эквивалентный запуск, который не поднимает встроенный broker и не подтягивает его через `depends_on`.

После генерации конфигурации запустите Backend и Engine и выполните end-to-end проверку пользовательской задачи и смены состояния.

### 7. Завершить миграцию

В течение периода наблюдения проверьте consumer lag, ошибки producer/consumer, дубликаты, пропуски, offsets и бизнес-события. Старый кластер оставьте остановленным, но сохраните его backup до завершения согласованного срока rollback.

Удаляйте старые данные только после отдельного подтверждения владельца данных.
