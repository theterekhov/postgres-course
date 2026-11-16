SET work_mem = '4MB';
SET random_page_cost = 1.1;

EXPLAIN (ANALYZE, BUFFERS)
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
