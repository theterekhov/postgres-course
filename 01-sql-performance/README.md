# SQL: разбор и оптимизация запроса

## Запрос

```sql
SELECT
  u.id,
  u.firstname,
  u.lastname,
  COUNT(m.id) AS received_messages
FROM users u
JOIN messages m
  ON u.id = m.to_user_id
GROUP BY u.id, u.firstname, u.lastname
ORDER BY received_messages DESC;
```

Считает, сколько входящих сообщений получил каждый пользователь, и сортирует список по убыванию. Соединение по `messages.to_user_id = users.id`, потом группировка по пользователю, `COUNT` считает сообщения. `JOIN` внутренний, поэтому у кого сообщений нет, тех в списке нет.

## Данные

PostgreSQL 18.6 в докере, порт 55435.

users: 200 000 строк, 18 МБ.
messages: 5 000 000 строк, 510 МБ.

Таблицы сделал `UNLOGGED`, чтобы быстрее залить данные. Сообщения распределены неравномерно, у части пользователей переписка активнее.

## План до оптимизации

```sql
SET work_mem = '4MB';

EXPLAIN (ANALYZE, BUFFERS)
SELECT
  u.id,
  u.firstname,
  u.lastname,
  COUNT(m.id) AS received_messages
FROM users u
JOIN messages m
  ON u.id = m.to_user_id
GROUP BY u.id, u.firstname, u.lastname
ORDER BY received_messages DESC;
```

Основное из плана:

```
Sort  (actual time=1141.235..1151.883 rows=199998)
  Sort Method: external merge  Disk: 9992kB
  ->  Partial HashAggregate  (actual time=894.679..977.274)
        Batches: 5  Memory Usage: 8249kB  Disk Usage: 28008kB
        ->  Parallel Hash Join  (actual time=18.825..571.397)
              ->  Parallel Seq Scan on messages m
              ->  Parallel Seq Scan on users u
```

1173 мс, прогоны 1285, 1155, 1174.

Что тормозит:

- seq scan по messages, читает все 510 МБ, а нужны только to_user_id и id;
- hash join по всем 5 млн сообщений;
- агрегация не влезла в 4 МБ, 5 батчей и 28 МБ на диск;
- сортировка по count тоже на диск, ещё 10 МБ.

## Индекс

```sql
CREATE INDEX messages_to_user_id_idx ON messages (to_user_id) INCLUDE (id);
VACUUM (ANALYZE) messages;
```

`INCLUDE (id)` чтобы запросу хватало одного индекса. VACUUM нужен, иначе index only scan всё равно ходит в таблицу.

```
->  Parallel Index Only Scan using messages_to_user_id_idx on messages m
      Heap Fetches: 0
->  Index Scan using users_pkey on users u
```

479 мс, прогоны 473, 479, 493.

## Переписал запрос

Сначала считаю сообщения по `to_user_id`, потом присоединяю имена. На агрегации строки уже, и соединять нужно 200 тыс. групп вместо 5 млн сообщений.

```sql
SELECT
  u.id,
  u.firstname,
  u.lastname,
  s.received_messages
FROM users u
JOIN (
  SELECT
    to_user_id,
    COUNT(*) AS received_messages
  FROM messages
  GROUP BY to_user_id
) s ON s.to_user_id = u.id
ORDER BY s.received_messages DESC;
```

```
->  Finalize HashAggregate  (actual time=201.942..232.919)
      Group Key: messages.to_user_id
      ->  Parallel Index Only Scan using messages_to_user_id_idx
->  Hash Join  (actual time=260.973..325.752 rows=199998)
```

Ещё поставил `random_page_cost = 1.1`, потому что диск SSD, а значение по умолчанию 4.0 завышает стоимость чтения по индексу. Получилось 378 мс, прогоны 378, 388, 375.

## Материализованное представление

Отчёт нужен регулярно, поэтому посчитал агрегацию заранее.

```sql
CREATE MATERIALIZED VIEW user_message_stats AS
SELECT
  u.id,
  u.firstname,
  u.lastname,
  COUNT(m.id) AS received_messages
FROM users u
JOIN messages m
  ON u.id = m.to_user_id
GROUP BY u.id, u.firstname, u.lastname;

CREATE UNIQUE INDEX user_message_stats_id_idx ON user_message_stats (id);
CREATE INDEX user_message_stats_received_idx ON user_message_stats (received_messages DESC);
```

```
Index Scan using user_message_stats_received_idx on user_message_stats
  (actual time=0.010..35.209 rows=199998)
```

40 мс на весь список и 0,03 мс на топ-10 с `LIMIT 10`. Обновлять так: `REFRESH MATERIALIZED VIEW CONCURRENTLY user_message_stats`, уникальный индекс для этого уже есть.

## Проверил work_mem

Отдельно попробовал просто поднять память. Стало хуже: 2706 мс. Планировщик выбрал seq scan и hash join без параллельности, потому что так дешевле по его оценке.

```
Sort  (actual time=2537.199..2562.176 rows=199998)
  Sort Method: quicksort  Memory: 17277kB
  ->  HashAggregate  (actual time=2485.642..2518.507)
        ->  Hash Join  (actual time=35.106..1494.474 rows=5000000.00)
              ->  Seq Scan on messages m
```

Вернул 4 МБ.

## Сколько получилось

| Вариант | Время |
|---|---|
| как было | 1173 мс |
| с индексом | 479 мс |
| индекс и переписанный запрос | 378 мс |
| материализованное представление | 40 мс |
| представление, топ-10 | 0,03 мс |
| work_mem 64 МБ | 2706 мс |

## Вывод

Индекс убирает чтение таблицы, переписывание уменьшает ширину строк и размер соединения. Сортировку по count индексом не заменить, поэтому для регулярного отчёта лучше представление. work_mem без проверки плана только мешает.

Замеры на одной машине, данные синтетические, кэш прогретый, поэтому на другом сервере цифры будут другие.

## Файлы

- `sql/01_schema.sql`, `sql/02_seed.sql`: схема и данные;
- `sql/03_explain_before.sql`: план до оптимизации;
- `sql/04_indexes.sql`: индекс;
- `sql/05_explain_after_rewrite.sql`: переписанный запрос;
- `sql/06_materialized_view.sql`, `sql/07_explain_view.sql`: представление и запрос к нему;
- `sql/08_work_mem_experiment.sql`: опыт с work_mem;
- `plans/`: сохранённые планы.
