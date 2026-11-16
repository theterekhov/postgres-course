CREATE INDEX messages_to_user_id_idx ON messages (to_user_id) INCLUDE (id);
VACUUM (ANALYZE) messages;
