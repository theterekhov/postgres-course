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
ANALYZE user_message_stats;
