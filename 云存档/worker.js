// ============================================================
// 大掌柜·云存档 Worker（Cloudflare Workers + D1）
// 接口：POST /register | POST /login | POST /upload | GET /download
// 原则：纯存储转发，不做任何数值校验（朋友间自娱自乐，开挂随意）
// 部署见「部署步骤.md」
// ============================================================

const CORS = {
	"Access-Control-Allow-Origin": "*",
	"Access-Control-Allow-Methods": "POST, GET, OPTIONS",
	"Access-Control-Allow-Headers": "Content-Type, Authorization",
}
const SESSION_DAYS = 30          // 登录令牌有效期（天）
const MAX_SAVE_SIZE = 8 * 1024 * 1024   // 存档上限 8MB，防手滑

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
			return json({ ok: false, msg: "未知接口" }, 404)
		} catch (e) {
			return json({ ok: false, msg: "服务器错误: " + String(e) }, 500)
		}
	},
}
