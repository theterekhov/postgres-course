EXPLAIN (ANALYZE, BUFFERS)
SELECT id, firstname, lastname, received_messages
FROM user_message_stats
ORDER BY received_messages DESC;
