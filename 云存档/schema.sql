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

-- 【新增】商会：record 为整包 JSON 字符串（等级/财富/成员/议事厅/人机），服务端不解析
CREATE TABLE IF NOT EXISTS guilds (
	id         TEXT PRIMARY KEY,
	name       TEXT NOT NULL,
	owner      TEXT NOT NULL,
	record     TEXT NOT NULL,
	updated_at INTEGER NOT NULL
);

-- 【新增】招商：真机项目（真人发布；joiners 为 JSON 数组，每条 {user,name,ts}）
CREATE TABLE IF NOT EXISTS zhaoshang_projects (
	id         TEXT PRIMARY KEY,
	owner      TEXT NOT NULL,
	owner_name TEXT NOT NULL,
	type       TEXT NOT NULL,
	copies     INTEGER NOT NULL,
	start_ts   INTEGER NOT NULL,
	end_ts     INTEGER NOT NULL,
	joiners    TEXT NOT NULL DEFAULT '[]',
	created_at INTEGER NOT NULL
);

-- 【新增】招商：五种资历周账（客户端结算自报，服务端不解析只做累加；周一 0 点 UTC+8 换 week_key 自然开新行）
CREATE TABLE IF NOT EXISTS zhaoshang_weekly (
	username      TEXT NOT NULL,
	name          TEXT NOT NULL,
	merit_shitu   INTEGER NOT NULL DEFAULT 0,
	merit_nongshi INTEGER NOT NULL DEFAULT 0,
	merit_jiangzao INTEGER NOT NULL DEFAULT 0,
	merit_xingshang INTEGER NOT NULL DEFAULT 0,
	merit_junshi  INTEGER NOT NULL DEFAULT 0,
	week_key      TEXT NOT NULL,
	updated_at    INTEGER NOT NULL,
	PRIMARY KEY (username, week_key)
);

-- 【新增】招商：点赞记录（唯一约束=每人每周一次；liker 是点赞方 username，target 是被赞方 username）
CREATE TABLE IF NOT EXISTS zhaoshang_likes (
	liker      TEXT NOT NULL,
	target     TEXT NOT NULL,
	week_key   TEXT NOT NULL,
	created_at INTEGER NOT NULL,
	UNIQUE (liker, week_key)
);

-- 【新增】好友：玩家名录（角色名→账号映射；进好友页自动登记，供按角色名搜索）
CREATE TABLE IF NOT EXISTS hy_names (
	username     TEXT PRIMARY KEY,
	display_name TEXT NOT NULL,
	updated_at   INTEGER NOT NULL
);

-- 【新增】好友：拜访档案（养成摘要 JSON，快照制：客户端进好友页自报，好友读取）
CREATE TABLE IF NOT EXISTS hy_profiles (
	username   TEXT PRIMARY KEY,
	profile    TEXT NOT NULL,
	updated_at INTEGER NOT NULL
);

-- 【新增】好友：点赞记录（唯一约束=每人每目标每天一次，重复点赞由约束挡下）
CREATE TABLE IF NOT EXISTS hy_likes (
	liker      TEXT NOT NULL,
	target     TEXT NOT NULL,
	day_key    TEXT NOT NULL,
	created_at INTEGER NOT NULL,
	PRIMARY KEY (liker, target, day_key)
);
