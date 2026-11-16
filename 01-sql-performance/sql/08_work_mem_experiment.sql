SET work_mem = '64MB';

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
