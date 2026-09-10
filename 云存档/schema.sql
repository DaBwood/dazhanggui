-- 大掌柜云存档 · D1 建表语句
-- 用法：wrangler d1 execute dazhanggui --file=schema.sql

CREATE TABLE IF NOT EXISTS users (
	username   TEXT PRIMARY KEY,
	salt       TEXT NOT NULL,
	pass_hash  TEXT NOT NULL,
	created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
	token    TEXT PRIMARY KEY,
	username TEXT NOT NULL,
	expires  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS saves (
	username   TEXT PRIMARY KEY,
	save_json  TEXT NOT NULL,
	updated_at INTEGER NOT NULL
);
