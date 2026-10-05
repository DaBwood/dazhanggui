// ============================================================
// 大掌柜·云存档 Worker（Cloudflare Workers + D1）
// 接口：POST /register | POST /login | POST /upload | GET /download
//       POST /guild/create | POST /guild/get | POST /guild/save   【新增】商会
// 原则：纯存储转发，不做任何数值校验（朋友间自娱自乐，开挂随意）
// 部署见「部署步骤.md」（商会需先执行 schema.sql 建 guilds 表）
// ============================================================

const CORS = {
	"Access-Control-Allow-Origin": "*",
	"Access-Control-Allow-Methods": "POST, GET, OPTIONS",
	"Access-Control-Allow-Headers": "Content-Type, Authorization",
}
const SESSION_DAYS = 30          // 登录令牌有效期（天）
const MAX_SAVE_SIZE = 8 * 1024 * 1024   // 存档上限 8MB，防手滑
const MAX_GUILD_SIZE = 1024 * 1024      // 【新增】商会记录上限 1MB（含人机名单，绰绰有余）

function json(data, status = 200) {
	return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json", ...CORS } })
}

// 加盐 SHA-256（Web Crypto 为 Worker 原生能力）
async function sha256(text) {
	const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text))
	return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, "0")).join("")
}

function randomToken() {
	const arr = new Uint8Array(24)
	crypto.getRandomValues(arr)
	return [...arr].map(b => b.toString(16).padStart(2, "0")).join("")
}

// 校验 Authorization: Bearer <token>，返回 username 或 null
async function auth(request, env) {
	const h = request.headers.get("Authorization") || ""
	const token = h.startsWith("Bearer ") ? h.slice(7) : ""
	if (!token) return null
	const row = await env.DB.prepare(
		"SELECT username FROM sessions WHERE token = ? AND expires > ?"
	).bind(token, Date.now()).first()
	return row ? row.username : null
}

async function makeSession(env, username) {
	const token = randomToken()
	const expires = Date.now() + SESSION_DAYS * 24 * 3600 * 1000
	await env.DB.prepare("INSERT INTO sessions (token, username, expires) VALUES (?, ?, ?)")
		.bind(token, username, expires).run()
	return json({ ok: true, token: token, username: username })
}

export default {
	async fetch(request, env) {
		if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS })
		const path = new URL(request.url).pathname
		try {
			// ---------- 注册 ----------
			if (path === "/register" && request.method === "POST") {
				const body = await request.json()
				const username = String(body.username || "").trim()
				const password = String(body.password || "")
				if (username.length < 2 || username.length > 16) return json({ ok: false, msg: "用户名需2~16个字符" }, 400)
				if (password.length < 4) return json({ ok: false, msg: "密码至少4位" }, 400)
				const exists = await env.DB.prepare("SELECT username FROM users WHERE username = ?").bind(username).first()
				if (exists) return json({ ok: false, msg: "用户名已被注册" }, 409)
				const salt = randomToken()
				const hash = await sha256(salt + ":" + password)
				await env.DB.prepare("INSERT INTO users (username, salt, pass_hash, created_at) VALUES (?, ?, ?, ?)")
					.bind(username, salt, hash, Date.now()).run()
				return await makeSession(env, username)
			}
			// ---------- 登录 ----------
			if (path === "/login" && request.method === "POST") {
				const { username, password } = await request.json()
				const u = await env.DB.prepare("SELECT * FROM users WHERE username = ?").bind(String(username || "")).first()
				if (!u) return json({ ok: false, msg: "用户名不存在" }, 401)
				const hash = await sha256(u.salt + ":" + String(password || ""))
				if (hash !== u.pass_hash) return json({ ok: false, msg: "密码错误" }, 401)
				return await makeSession(env, u.username)
			}
			// ---------- 上传存档（后存覆盖先存） ----------
			if (path === "/upload" && request.method === "POST") {
				const username = await auth(request, env)
				if (!username) return json({ ok: false, msg: "未登录或会话已过期" }, 401)
				const { save } = await request.json()
				if (typeof save !== "string" || save.length === 0) return json({ ok: false, msg: "存档内容为空" }, 400)
				if (save.length > MAX_SAVE_SIZE) return json({ ok: false, msg: "存档超过8MB上限" }, 400)
				const now = Date.now()
				await env.DB.prepare(
					"INSERT INTO saves (username, save_json, updated_at) VALUES (?, ?, ?) " +
					"ON CONFLICT(username) DO UPDATE SET save_json = excluded.save_json, updated_at = excluded.updated_at"
				).bind(username, save, now).run()
				return json({ ok: true, updated_at: now })
			}
			// ---------- 下载存档 ----------
			if (path === "/download" && request.method === "GET") {
				const username = await auth(request, env)
				if (!username) return json({ ok: false, msg: "未登录或会话已过期" }, 401)
				const row = await env.DB.prepare("SELECT save_json, updated_at FROM saves WHERE username = ?").bind(username).first()
				if (!row) return json({ ok: true, has_save: false })
				return json({ ok: true, has_save: true, save: row.save_json, updated_at: row.updated_at })
			}
			// ============================================================
			// 【新增】商会：guilds 表整包存取（record 为 JSON 字符串，服务端不解析不校验）
			// 设计：后存覆盖先存（同存档哲学）；成员身份由客户端自行维护，服务端只认登录态
			// ============================================================
			// ---------- 创建商会 ----------
			if (path === "/guild/create" && request.method === "POST") {
				const username = await auth(request, env)
				if (!username) return json({ ok: false, msg: "未登录或会话已过期" }, 401)
				const body = await request.json()
				const name = String(body.name || "").trim()
				if (name.length < 2 || name.length > 16) return json({ ok: false, msg: "商会名需2~16个字符" }, 400)
				const dup = await env.DB.prepare("SELECT id FROM guilds WHERE name = ?").bind(name).first()
				if (dup) return json({ ok: false, msg: "商会名已存在" }, 409)
				const id = randomToken().slice(0, 16)   // 16位邀请码
				const now = Date.now()
				// 记录结构（客户端约定，服务端只存）：等级/财富/经验/成员/议事厅/人机结算日
				const record = {
					"name": name, "owner": username, "created": now,   // 【修】误写 GDScript 的 int()，JS 无此函数导致 500
					"level": 1, "exp": 0, "wealth": 0,
					"members": [{ "user": username, "name": username, "role": "owner" }],
					"council": {}, "bot_settle": "",
				}
				await env.DB.prepare("INSERT INTO guilds (id, name, owner, record, updated_at) VALUES (?, ?, ?, ?, ?)")
					.bind(id, name, username, JSON.stringify(record), now).run()
				return json({ ok: true, guild_id: id, record: record })
			}
			// ---------- 查询商会 ----------
			if (path === "/guild/get" && request.method === "POST") {
				const username = await auth(request, env)
				if (!username) return json({ ok: false, msg: "未登录或会话已过期" }, 401)
				const body = await request.json()
				const row = await env.DB.prepare("SELECT record FROM guilds WHERE id = ?").bind(String(body.guild_id || "")).first()
				if (!row) return json({ ok: false, msg: "商会不存在" }, 404)
				return json({ ok: true, record: JSON.parse(row.record) })
			}
			// ---------- 回写商会（整包覆盖） ----------
			if (path === "/guild/save" && request.method === "POST") {
				const username = await auth(request, env)
				if (!username) return json({ ok: false, msg: "未登录或会话已过期" }, 401)
				const body = await request.json()
				const recStr = JSON.stringify(body.record || {})
				if (recStr.length > MAX_GUILD_SIZE) return json({ ok: false, msg: "商会记录超过1MB上限" }, 400)
				const r = await env.DB.prepare("UPDATE guilds SET record = ?, updated_at = ? WHERE id = ?")
					.bind(recStr, Date.now(), String(body.guild_id || "")).run()
				if (r.meta.changes === 0) return json({ ok: false, msg: "商会不存在" }, 404)
				return json({ ok: true })
			}
			// ---------- 招商：发布项目（幂等：id 由客户端生成，重试/补报重复提交安全） ----------
			if (path === "/zhaoshang/publish" && request.method === "POST") {
				const username = await auth(request, env)
				if (!username) return json({ ok: false, msg: "未登录或会话已过期" }, 401)
				const body = await request.json()
				const id = String(body.id || "")
				if (!id) return json({ ok: false, msg: "缺少项目id" }, 400)
				const now = Math.floor(Date.now() / 1000)
				await env.DB.prepare("INSERT INTO zhaoshang_projects (id, owner, owner_name, type, copies, start_ts, end_ts, joiners, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, '[]', ?) ON CONFLICT(id) DO UPDATE SET owner_name = excluded.owner_name, type = excluded.type, copies = excluded.copies, start_ts = excluded.start_ts, end_ts = excluded.end_ts")
					.bind(id, username, String(body.owner_name || username), String(body.type || ""), Math.max(1, Math.min(4, parseInt(body.copies) || 1)), parseInt(body.start_ts) || now, parseInt(body.end_ts) || now, now).run()
				return json({ ok: true })
			}
			// ---------- 招商：加入项目（读-改-写；单线程朋友局并发可接受） ----------
			if (path === "/zhaoshang/join" && request.method === "POST") {
				const username = await auth(request, env)
				if (!username) return json({ ok: false, msg: "未登录或会话已过期" }, 401)
				const body = await request.json()
				const row = await env.DB.prepare("SELECT * FROM zhaoshang_projects WHERE id = ?").bind(String(body.project_id || "")).first()
				if (!row) return json({ ok: false, msg: "项目不存在" }, 404)
				const now = Math.floor(Date.now() / 1000)
				if (parseInt(row.end_ts) <= now) return json({ ok: false, msg: "项目已结束" }, 409)
				let joiners = []
				try { joiners = JSON.parse(row.joiners || "[]") } catch (e) { joiners = [] }
				if (joiners.length >= 4) return json({ ok: false, msg: "项目已满员" }, 409)
				if (joiners.some(function (j) { return j.user === username })) return json({ ok: false, msg: "已加入该项目" }, 409)
				joiners.push({ user: username, name: String(body.name || username), ts: now })
				await env.DB.prepare("UPDATE zhaoshang_projects SET joiners = ? WHERE id = ?").bind(JSON.stringify(joiners), String(body.project_id || "")).run()
				return json({ ok: true, end_ts: parseInt(row.end_ts), type: row.type })
			}
			// ---------- 招商：周资历上报（服务端不解析，只做五列累加；week_key 换周自然开新行） ----------
			if (path === "/zhaoshang/merit" && request.method === "POST") {
				const username = await auth(request, env)
				if (!username) return json({ ok: false, msg: "未登录或会话已过期" }, 401)
				const body = await request.json()
				const deltas = body.deltas || {}
				const weekKey = String(body.week_key || "")
				if (!weekKey) return json({ ok: false, msg: "缺少周键" }, 400)
				const num = function (v) { const n = parseInt(v); return isNaN(n) ? 0 : Math.max(0, n) }
				await env.DB.prepare("INSERT INTO zhaoshang_weekly (username, name, merit_shitu, merit_nongshi, merit_jiangzao, merit_xingshang, merit_junshi, week_key, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(username, week_key) DO UPDATE SET name = excluded.name, merit_shitu = merit_shitu + excluded.merit_shitu, merit_nongshi = merit_nongshi + excluded.merit_nongshi, merit_jiangzao = merit_jiangzao + excluded.merit_jiangzao, merit_xingshang = merit_xingshang + excluded.merit_xingshang, merit_junshi = merit_junshi + excluded.merit_junshi, updated_at = excluded.updated_at")
					.bind(username, String(body.name || username), num(deltas.shitu), num(deltas.nongshi), num(deltas.jiangzao), num(deltas.xingshang), num(deltas.junshi), weekKey, Date.now()).run()
				return json({ ok: true })
			}
			// ---------- 招商：点赞（唯一约束=每人每周一次，重复点赞由约束挡下） ----------
			if (path === "/zhaoshang/like" && request.method === "POST") {
				const username = await auth(request, env)
				if (!username) return json({ ok: false, msg: "未登录或会话已过期" }, 401)
				const body = await request.json()
				const weekKey = String(body.week_key || "")
				const target = String(body.target || "")
				if (!weekKey || !target) return json({ ok: false, msg: "参数不全" }, 400)
				try {
					await env.DB.prepare("INSERT INTO zhaoshang_likes (liker, target, week_key, created_at) VALUES (?, ?, ?, ?)").bind(username, target, weekKey, Date.now()).run()
				} catch (e) {
					return json({ ok: false, msg: "本周已点赞" }, 409)
				}
				return json({ ok: true })
			}
			// ---------- 招商：进行中且有空位的真机项目（排除自己的；joiners 在服务端数） ----------
			if (path === "/zhaoshang/projects" && request.method === "GET") {
				const username = await auth(request, env)
				if (!username) return json({ ok: false, msg: "未登录或会话已过期" }, 401)
				const now = Math.floor(Date.now() / 1000)
				const rs = await env.DB.prepare("SELECT * FROM zhaoshang_projects WHERE end_ts > ? ORDER BY created_at ASC LIMIT 50").bind(now).all()
				const out = []
				for (const row of (rs.results || [])) {
					if (row.owner === username) continue
					let joiners = []
					try { joiners = JSON.parse(row.joiners || "[]") } catch (e) { joiners = [] }
					if (joiners.length >= 4) continue
					out.push({ id: row.id, owner_name: row.owner_name, type: row.type, copies: parseInt(row.copies), start_ts: parseInt(row.start_ts), end_ts: parseInt(row.end_ts), joined: joiners.length, slots: 4 })
				}
				return json({ ok: true, projects: out })
			}
			// ---------- 招商：名流榜分榜（merit 列名白名单防注入，top50） ----------
			if (path === "/zhaoshang/leaderboard" && request.method === "GET") {
				const qs = new URL(request.url).searchParams
				const meritCol = { shitu: "merit_shitu", nongshi: "merit_nongshi", jiangzao: "merit_jiangzao", xingshang: "merit_xingshang", junshi: "merit_junshi" }[qs.get("merit") || ""]
				const weekKey = String(qs.get("week") || "")
				if (!meritCol || !weekKey) return json({ ok: false, msg: "参数不全" }, 400)
				const rs = await env.DB.prepare("SELECT username, name, " + meritCol + " AS merit FROM zhaoshang_weekly WHERE week_key = ? ORDER BY merit DESC LIMIT 50").bind(weekKey).all()
				return json({ ok: true, list: rs.results || [] })
			}
			// ---------- 好友：登记角色名（名录 upsert；进好友页即自报，供他人搜索） ----------
			if (path === "/hy/name" && request.method === "POST") {
				const name = String(body.name || "").trim()
				if (name === "") return json({ ok: false, msg: "角色名不能为空" }, 400)
				await env.DB.prepare("INSERT INTO hy_names (username, display_name, updated_at) VALUES (?, ?, ?) ON CONFLICT(username) DO UPDATE SET display_name = ?, updated_at = ?").bind(sess.username, name, now, name, now).run()
				return json({ ok: true })
			}
			// ---------- 好友：按角色名搜索（排除自己，LIMIT 由配置封顶防拖库） ----------
			if (path === "/hy/search" && request.method === "GET") {
				const qs = new URL(request.url).searchParams
				const kw = String(qs.get("keyword") || "").trim()
				if (kw === "") return json({ ok: false, msg: "请输入角色名" }, 400)
				const rs = await env.DB.prepare("SELECT username, display_name FROM hy_names WHERE display_name LIKE ? AND username != ? ORDER BY updated_at DESC LIMIT ?").bind("%" + kw + "%", sess.username, 20).all()
				return json({ ok: true, list: rs.results || [] })
			}
			// ---------- 好友：拜访档案上传（快照制；整包覆盖，客户端每次进好友页自报） ----------
			if (path === "/hy/profile" && request.method === "POST") {
				const profile = JSON.stringify(body.profile || {})
				if (profile.length > 256 * 1024) return json({ ok: false, msg: "档案过大" }, 400)
				await env.DB.prepare("INSERT INTO hy_profiles (username, profile, updated_at) VALUES (?, ?, ?) ON CONFLICT(username) DO UPDATE SET profile = ?, updated_at = ?").bind(sess.username, profile, now, profile, now).run()
				return json({ ok: true })
			}
			// ---------- 好友：拜访档案读取（对方没传过=404 暂无档案） ----------
			if (path === "/hy/profile/get" && request.method === "POST") {
				const target = String(body.user || "")
				if (target === "") return json({ ok: false, msg: "参数不全" }, 400)
				const row = await env.DB.prepare("SELECT profile FROM hy_profiles WHERE username = ?").bind(target).first()
				if (!row) return json({ ok: false, msg: "暂无档案" }, 404)
				return json({ ok: true, profile: JSON.parse(row.profile || "{}") })
			}
			// ---------- 好友：点赞（唯一约束=每人每目标每天一次，重复点赞由约束挡下返回409） ----------
			if (path === "/hy/like" && request.method === "POST") {
				const target = String(body.target || "")
				const dayKey = String(body.day || "")
				if (target === "" || dayKey === "") return json({ ok: false, msg: "参数不全" }, 400)
				try {
					await env.DB.prepare("INSERT INTO hy_likes (liker, target, day_key, created_at) VALUES (?, ?, ?, ?)").bind(sess.username, target, dayKey, now).run()
					return json({ ok: true })
				} catch (e) {
					return json({ ok: false, msg: "今日已赞过" }, 409)
				}
			}
			// ---------- 好友：我今日已赞清单（多设备对齐，服务器为准） ----------
			if (path === "/hy/likes" && request.method === "GET") {
				const qs = new URL(request.url).searchParams
				const dayKey = String(qs.get("day") || "")
				if (dayKey === "") return json({ ok: false, msg: "参数不全" }, 400)
				const rs = await env.DB.prepare("SELECT target FROM hy_likes WHERE liker = ? AND day_key = ?").bind(sess.username, dayKey).all()
				return json({ ok: true, list: (rs.results || []).map(function (r) { return r.target }) })
			}
			return json({ ok: false, msg: "未知接口" }, 404)
		} catch (e) {
			return json({ ok: false, msg: "服务器错误: " + String(e) }, 500)
		}
	},
}
