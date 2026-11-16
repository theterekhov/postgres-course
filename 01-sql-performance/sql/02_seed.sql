INSERT INTO users (id, firstname, lastname, created_at)
SELECT
  i,
  (ARRAY['Анна','Иван','Мария','Пётр','Ольга','Сергей','Елена','Дмитрий'])[1 + (i % 8)],
  (ARRAY['Иванова','Петров','Смирнова','Кузнецов','Попова','Соколов','Лебедева','Новиков'])[1 + ((i * 7) % 8)],
  timestamp '2023-01-01' + (i % 700) * interval '1 day'
FROM generate_series(1, 200000) AS i;

INSERT INTO messages (id, from_user_id, to_user_id, body, created_at)
SELECT
  i,
  1 + (random() * 199999)::int,
  1 + (power(random(), 3) * 199999)::int,
  'Сообщение №' || i,
  timestamp '2024-01-01' + (random() * 500) * interval '1 day'
FROM generate_series(1, 5000000) AS i;
