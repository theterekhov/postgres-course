DROP TABLE IF EXISTS messages;
DROP TABLE IF EXISTS users;

CREATE UNLOGGED TABLE users (
  id integer PRIMARY KEY,
  firstname text NOT NULL,
  lastname text NOT NULL,
  created_at timestamp NOT NULL
);

CREATE UNLOGGED TABLE messages (
  id bigint PRIMARY KEY,
  from_user_id integer NOT NULL,
  to_user_id integer NOT NULL,
  body text NOT NULL,
  created_at timestamp NOT NULL
);
