// ============================================================
// 大掌柜·国内云存档服务（Node.js 零依赖，替代 Cloudflare Worker + D1）
// 接口与 云存档/worker.js 逐一对齐（19 个路由），JSON 文件存储（data/*.json），原子写入
// 原则不变：纯存储转发，不做数值校验（朋友间自娱自乐，开挂随意）
// 用法：node server.js   默认端口 8787（云控制台安全组 + 系统防火墙都要放行 TCP 8787）
// 存储口径：一张表一个 JSON 文件，启动全量载入内存，写时 tmp+rename 原子落盘
// ============================================================
const http = require("http")
const https = require("https")
const fs = require("fs")
const path = require("path")
const crypto = require("crypto")
const { spawnSync } = require("child_process")

const PORT = 8787          // HTTP：原生 App 导出用（无浏览器安全策略限制）
const HTTPS_PORT = 8788    // HTTPS（自签名）：浏览器/手机网页测试用——Godot Web 强制 isSecureContext，HTTPS 页面又禁止调 HTTP 接口
const CERT_FILE = path.join(__dirname, "cert.pem")
const KEY_FILE = path.join(__dirname, "key.pem")
const SESSION_DAYS = 30
const MAX_SAVE_SIZE = 8 * 1024 * 1024     // 存档上限 8MB（与 Worker 版一致）
const MAX_GUILD_SIZE = 1024 * 1024        // 商会记录上限 1MB
const MAX_PROFILE_SIZE = 256 * 1024       // 拜访档案上限 256KB（与 Worker 版一致）
const MAX_BODY_SIZE = 10 * 1024 * 1024    // 请求体硬顶 10MB（存档 8MB + 冗余）
const DATA_DIR = path.join(__dirname, "data")

// ---------- JSON 文件表 ----------
const TABLES = ["users", "sessions", "saves", "guilds",
	"zhaoshang_projects", "zhaoshang_weekly", "zhaoshang_likes",
	"hy_names", "hy_profiles", "hy_likes"]
var db = {}

function loadTable(name) {
	const file = path.join(DATA_DIR, name + ".json")
	try {
		db[name] = JSON.parse(fs.readFileSync(file, "utf8"))
	} catch (e) {
		db[name] = {}
	}
}

function saveTable(name) {
	const file = path.join(DATA_DIR, name + ".json")
	const tmp = file + ".tmp"
	fs.writeFileSync(tmp, JSON.stringify(db[name]))
	fs.renameSync(tmp, file)   // 原子换名：崩溃要么旧文件要么新文件，不留半截
}

function sha256(text) {
	return crypto.createHash("sha256").update(text, "utf8").digest("hex")
}

function randomToken() {
	return crypto.randomBytes(24).toString("hex")   // 48位hex，与 Worker 版同形
}

const CORS = {
	"Access-Control-Allow-Origin": "*",
	"Access-Control-Allow-Methods": "POST, GET, OPTIONS",
	"Access-Control-Allow-Headers": "Content-Type, Authorization",
}

function json(data, status) {
	if (status === undefined) status = 200
	return [status, JSON.stringify(data)]
}

// 校验 Authorization: Bearer <token>，返回 username 或 null（过期会话等同未登录）
function auth(headers) {
	const h = headers["authorization"] || ""
	const token = h.startsWith("Bearer ") ? h.slice(7) : ""
	if (!token) return null
	const s = db.sessions[token]
	if (!s || s.expires <= Date.now()) return null
	return s.username
}

function makeSession(username) {
	const token = randomToken()
	db.sessions[token] = { username: username, expires: Date.now() + SESSION_DAYS * 24 * 3600 * 1000 }
	saveTable("sessions")
	return json({ ok: true, token: token, username: username })
}

// ---------- 请求体读取（空体返回 {}；超限 413） ----------
function readBody(req, cb) {
	const chunks = []
	var size = 0
	req.on("data", function (c) {
		size += c.length
		if (size > MAX_BODY_SIZE) {
			req.destroy()
			cb(null)
			return
		}
		chunks.push(c)
	})
	req.on("end", function () {
		if (size === 0) { cb({}); return }
		try {
			cb(JSON.parse(Buffer.concat(chunks).toString("utf8")))
		} catch (e) {
			cb(null)
		}
	})
	req.on("error", function () { cb(null) })
}

// ---------- 路由 ----------
const routes = {
	// ---------- 注册 ----------
	"POST /register": function (body, user) {
		const username = String(body.username || "").trim()
		const password = String(body.password || "")
		if (username.length < 2 || username.length > 16) return json({ ok: false, msg: "用户名需2~16个字符" }, 400)
		if (!/^[\w\u4e00-\u9fa5]{2,16}$/.test(username)) return json({ ok: false, msg: "用户名只允许中英文、数字、下划线" }, 400)
		if (password.length < 4) return json({ ok: false, msg: "密码至少4位" }, 400)
		if (db.users[username]) return json({ ok: false, msg: "用户名已被注册" }, 409)
		const salt = randomToken()
		db.users[username] = { salt: salt, pass_hash: sha256(salt + ":" + password), created_at: Date.now() }
		saveTable("users")
		return makeSession(username)
	},
	// ---------- 登录 ----------
	"POST /login": function (body, user) {
		// 与注册同口径 trim：手机输入法常带尾随空格，不 trim 会"注册成功却永远登录不了"
		const uname = String(body.username || "").trim()
		const u = db.users[uname]
		if (!u) return json({ ok: false, msg: "用户名不存在" }, 401)
		if (sha256(u.salt + ":" + String(body.password || "")) !== u.pass_hash) return json({ ok: false, msg: "密码错误" }, 401)
		return makeSession(uname)
	},
	// ---------- 上传存档（后存覆盖先存） ----------
	"POST /upload": function (body, user) {
		const save = body.save
		if (typeof save !== "string" || save.length === 0) return json({ ok: false, msg: "存档内容为空" }, 400)
		if (save.length > MAX_SAVE_SIZE) return json({ ok: false, msg: "存档超过8MB上限" }, 400)
		const now = Date.now()
		db.saves[user] = { save_json: save, updated_at: now }
		saveTable("saves")
		return json({ ok: true, updated_at: now })
	},
	// ---------- 下载存档 ----------
	"GET /download": function (body, user) {
		const row = db.saves[user]
		if (!row) return json({ ok: true, has_save: false })
		return json({ ok: true, has_save: true, save: row.save_json, updated_at: row.updated_at })
	},
	// ---------- 创建商会 ----------
	"POST /guild/create": function (body, user) {
		const name = String(body.name || "").trim()
		if (name.length < 2 || name.length > 16) return json({ ok: false, msg: "商会名需2~16个字符" }, 400)
		for (const id in db.guilds) {
			if (db.guilds[id].name === name) return json({ ok: false, msg: "商会名已存在" }, 409)
		}
		// 4位数字邀请码（1000~9999，易读易传播）；1万空间对商会数量足够，冲突重roll（内存表直查）
		let gid = ""
		for (let _t = 0; _t < 20; _t++) {
			gid = String(Math.floor(1000 + Math.random() * 9000))
			if (!db.guilds[gid]) break
			gid = ""
		}
		if (gid === "") return json({ ok: false, msg: "邀请码生成冲突，请重试" }, 409)
		const now = Date.now()
		// 记录结构（客户端约定，服务端只存）：等级/财富/经验/成员/议事厅/人机结算日
		const record = {
			"name": name, "owner": user, "created": now,
			"level": 1, "exp": 0, "wealth": 0,
			"members": [{ "user": user, "name": user, "role": "owner" }],
			"council": {}, "bot_settle": "",
		}
		db.guilds[gid] = { name: name, owner: user, record: JSON.stringify(record), updated_at: now }
		saveTable("guilds")
		return json({ ok: true, guild_id: gid, record: record })
	},
	// ---------- 查询商会 ----------
	"POST /guild/get": function (body, user) {
		const row = db.guilds[String(body.guild_id || "")]
		if (!row) return json({ ok: false, msg: "商会不存在" }, 404)
		return json({ ok: true, record: JSON.parse(row.record) })
	},
	// ---------- 回写商会（整包覆盖；id 不存在=404） ----------
	"POST /guild/save": function (body, user) {
		const recStr = JSON.stringify(body.record || {})
		if (recStr.length > MAX_GUILD_SIZE) return json({ ok: false, msg: "商会记录超过1MB上限" }, 400)
		const row = db.guilds[String(body.guild_id || "")]
		if (!row) return json({ ok: false, msg: "商会不存在" }, 404)
		// 权限闸：只有会长或成员能回写（disband 有 owner 校验，此处此前漏了——实测任意登录用户可整包改写任意商会）
		let rec = {}
		try { rec = JSON.parse(row.record || "{}") } catch (e) { rec = {} }
		if (rec.owner !== user && !(rec.members || []).some(function (m) { return m.user === user }))
			return json({ ok: false, msg: "不是该商会成员，无权回写" }, 403)
		row.record = recStr
		row.updated_at = Date.now()
		saveTable("guilds")
		return json({ ok: true })
	},
	// ---------- 解散商会（仅会长；删整行，成员端靠 guild/get 404 死引用自愈清档） ----------
	"POST /guild/disband": function (body, user) {
		const gid = String(body.guild_id || "")
		const row = db.guilds[gid]
		if (!row) return json({ ok: false, msg: "商会不存在" }, 404)
		if (row.owner !== user) return json({ ok: false, msg: "只有会长可以解散商会" }, 403)
		delete db.guilds[gid]
		saveTable("guilds")
		return json({ ok: true })
	},
	// ---------- 招商：发布项目（幂等：id 由客户端生成，重复提交=覆盖可变字段） ----------
	"POST /zhaoshang/publish": function (body, user) {
		const id = String(body.id || "")
		if (!id) return json({ ok: false, msg: "缺少项目id" }, 400)
		const now = Math.floor(Date.now() / 1000)
		const old = db.zhaoshang_projects[id]
		if (old) {
			// ON CONFLICT 语义：只刷新可变展示字段，不动 owner/joiners/created_at
			old.owner_name = String(body.owner_name || user)
			old.type = String(body.type || "")
			old.copies = Math.max(1, Math.min(4, parseInt(body.copies) || 1))
			old.start_ts = parseInt(body.start_ts) || now
			old.end_ts = parseInt(body.end_ts) || now
		} else {
			db.zhaoshang_projects[id] = {
				owner: user, owner_name: String(body.owner_name || user), type: String(body.type || ""),
				copies: Math.max(1, Math.min(4, parseInt(body.copies) || 1)),
				start_ts: parseInt(body.start_ts) || now, end_ts: parseInt(body.end_ts) || now,
				joiners: "[]", created_at: now,
			}
		}
		saveTable("zhaoshang_projects")
		return json({ ok: true })
	},
	// ---------- 招商：加入项目（读-改-写；单线程朋友局并发可接受） ----------
	"POST /zhaoshang/join": function (body, user) {
		const row = db.zhaoshang_projects[String(body.project_id || "")]
		if (!row) return json({ ok: false, msg: "项目不存在" }, 404)
		const now = Math.floor(Date.now() / 1000)
		if (parseInt(row.end_ts) <= now) return json({ ok: false, msg: "项目已结束" }, 409)
		var joiners = []
		try { joiners = JSON.parse(row.joiners || "[]") } catch (e) { joiners = [] }
		if (joiners.length >= 4) return json({ ok: false, msg: "项目已满员" }, 409)
		for (const j2 of joiners) { if (j2.user === user) return json({ ok: false, msg: "已加入该项目" }, 409) }
		joiners.push({ user: user, name: String(body.name || user), ts: now })
		row.joiners = JSON.stringify(joiners)
		saveTable("zhaoshang_projects")
		return json({ ok: true, end_ts: parseInt(row.end_ts), type: row.type })
	},
	// ---------- 招商：周资历上报（服务端不解析，只做五列累加；换周自然开新行） ----------
	"POST /zhaoshang/merit": function (body, user) {
		const deltas = body.deltas || {}
		const weekKey = String(body.week_key || "")
		if (!weekKey) return json({ ok: false, msg: "缺少周键" }, 400)
		const num = function (v) { const n = parseInt(v); return isNaN(n) ? 0 : Math.max(0, n) }
		const key = user + "|" + weekKey
		const old = db.zhaoshang_weekly[key]
		if (old) {
			old.name = String(body.name || user)
			old.merit_shitu += num(deltas.shitu)
			old.merit_nongshi += num(deltas.nongshi)
			old.merit_jiangzao += num(deltas.jiangzao)
			old.merit_xingshang += num(deltas.xingshang)
			old.merit_junshi += num(deltas.junshi)
			old.updated_at = Date.now()
		} else {
			db.zhaoshang_weekly[key] = {
				username: user, name: String(body.name || user),
				merit_shitu: num(deltas.shitu), merit_nongshi: num(deltas.nongshi),
				merit_jiangzao: num(deltas.jiangzao), merit_xingshang: num(deltas.xingshang),
				merit_junshi: num(deltas.junshi),
				week_key: weekKey, updated_at: Date.now(),
			}
		}
		saveTable("zhaoshang_weekly")
		return json({ ok: true })
	},
	// ---------- 招商：点赞（唯一约束=每人每周一次，重复点赞 409） ----------
	"POST /zhaoshang/like": function (body, user) {
		const weekKey = String(body.week_key || "")
		const target = String(body.target || "")
		if (!weekKey || !target) return json({ ok: false, msg: "参数不全" }, 400)
		const key = user + "|" + target + "|" + weekKey
		if (db.zhaoshang_likes[key]) return json({ ok: false, msg: "本周已点赞" }, 409)
		db.zhaoshang_likes[key] = { liker: user, target: target, week_key: weekKey, created_at: Date.now() }
		saveTable("zhaoshang_likes")
		return json({ ok: true })
	},
	// ---------- 招商：进行中且有空位的真机项目（排除自己的） ----------
	"GET /zhaoshang/projects": function (body, user) {
		const now = Math.floor(Date.now() / 1000)
		const rows = Object.values(db.zhaoshang_projects)
			.filter(function (r) { return parseInt(r.end_ts) > now })
			.sort(function (a, b) { return a.created_at - b.created_at })
		const out = []
		for (const row of rows) {
			if (row.owner === user) continue
			var joiners = []
			try { joiners = JSON.parse(row.joiners || "[]") } catch (e) { joiners = [] }
			if (joiners.length >= 4) continue
			out.push({ id: row.id, owner_name: row.owner_name, type: row.type, copies: parseInt(row.copies), start_ts: parseInt(row.start_ts), end_ts: parseInt(row.end_ts), joined: joiners.length, slots: 4 })
		}
		return json({ ok: true, projects: out.slice(0, 50) })
	},
	// ---------- 招商：名流榜分榜（merit 键白名单防注入，top50） ----------
	"GET /zhaoshang/leaderboard": function (body, user, query) {
		const colMap = { shitu: "merit_shitu", nongshi: "merit_nongshi", jiangzao: "merit_jiangzao", xingshang: "merit_xingshang", junshi: "merit_junshi" }
		const meritCol = colMap[String(query.merit || "")] || ""
		const weekKey = String(query.week || "")
		if (!meritCol || !weekKey) return json({ ok: false, msg: "参数不全" }, 400)
		const list = Object.values(db.zhaoshang_weekly)
			.filter(function (r) { return r.week_key === weekKey })
			.map(function (r) { return { username: r.username, name: r.name, merit: parseInt(r[meritCol]) || 0 } })
			.sort(function (a, b) { return b.merit - a.merit })
			.slice(0, 50)
		return json({ ok: true, list: list })
	},
	// ---------- 好友：登记角色名（名录 upsert；进好友页即自报，供他人搜索） ----------
	"POST /hy/name": function (body, user) {
		const name = String(body.name || "").trim()
		if (name === "") return json({ ok: false, msg: "角色名不能为空" }, 400)
		db.hy_names[user] = { display_name: name, updated_at: Date.now() }
		saveTable("hy_names")
		return json({ ok: true })
	},
	// ---------- 好友：按角色名搜索（排除自己，上限20条防拖库） ----------
	"GET /hy/search": function (body, user, query) {
		const kw = String(query.keyword || "").trim()
		if (kw === "") return json({ ok: false, msg: "请输入角色名" }, 400)
		const out = []
		for (const uname in db.hy_names) {
			if (uname === user) continue
			const rec = db.hy_names[uname]
			if (String(rec.display_name).indexOf(kw) >= 0) {
				out.push({ username: uname, display_name: rec.display_name, updated_at: rec.updated_at })
			}
			if (out.length >= 20) break
		}
		out.sort(function (a, b) { return b.updated_at - a.updated_at })
		return json({ ok: true, list: out.slice(0, 20) })
	},
	// ---------- 好友：拜访档案上传（快照制；整包覆盖，客户端每次进好友页自报） ----------
	"POST /hy/profile": function (body, user) {
		const profile = JSON.stringify(body.profile || {})
		if (profile.length > MAX_PROFILE_SIZE) return json({ ok: false, msg: "档案过大" }, 400)
		db.hy_profiles[user] = { profile: profile, updated_at: Date.now() }
		saveTable("hy_profiles")
		return json({ ok: true })
	},
	// ---------- 好友：拜访档案读取（对方没传过=404 暂无档案） ----------
	"POST /hy/profile/get": function (body, user) {
		const target = String(body.user || "")
		if (target === "") return json({ ok: false, msg: "参数不全" }, 400)
		const row = db.hy_profiles[target]
		if (!row) return json({ ok: false, msg: "暂无档案" }, 404)
		return json({ ok: true, profile: JSON.parse(row.profile) })
	},
	// ---------- 好友：点赞（唯一约束=每人每目标每天一次，重复点赞 409） ----------
	"POST /hy/like": function (body, user) {
		const target = String(body.target || "")
		const dayKey = String(body.day || "")
		if (target === "" || dayKey === "") return json({ ok: false, msg: "参数不全" }, 400)
		const key = user + "|" + target + "|" + dayKey
		if (db.hy_likes[key]) return json({ ok: false, msg: "今日已赞过" }, 409)
		db.hy_likes[key] = { liker: user, target: target, day_key: dayKey, created_at: Date.now() }
		saveTable("hy_likes")
		return json({ ok: true })
	},
	// ---------- 好友：我今日已赞清单（多设备对齐，服务器为准） ----------
	"GET /hy/likes": function (body, user, query) {
		const dayKey = String(query.day || "")
		if (dayKey === "") return json({ ok: false, msg: "参数不全" }, 400)
		const out = []
		for (const key in db.hy_likes) {
			const rec = db.hy_likes[key]
			if (rec.liker === user && rec.day_key === dayKey) out.push(rec.target)
		}
		return json({ ok: true, list: out })
	},
}

// ---------- HTTP/HTTPS 服务（同一 handler，双协议并存） ----------
function handleRequest(req, res) {
		res.setHeader("Content-Type", "application/json")
		for (const k in CORS) res.setHeader(k, CORS[k])
		if (req.method === "OPTIONS") { res.statusCode = 204; res.end(); return }
		const u = new URL(req.url, "http://localhost")
		const handler = routes[req.method + " " + u.pathname]
		readBody(req, function (body) {
			try {
				if (!handler) { res.statusCode = 404; res.end(JSON.stringify({ ok: false, msg: "未知接口" })); return }
				if (body === null) { res.statusCode = 400; res.end(JSON.stringify({ ok: false, msg: "请求体解析失败" })); return }
				const user = auth(req.headers)
				// 除注册/登录外全部要求登录态（与 Worker 版逐接口一致）
				if (req.method + " " + u.pathname !== "POST /register" && req.method + " " + u.pathname !== "POST /login" && !user) {
					res.statusCode = 401
					res.end(JSON.stringify({ ok: false, msg: "未登录或会话已过期" }))
					return
				}
				const query = {}
				u.searchParams.forEach(function (v, k) { query[k] = v })
				const out = handler(body, user, query)
				res.statusCode = out[0]
				res.end(out[1])
			} catch (e) {
				res.statusCode = 500
				res.end(JSON.stringify({ ok: false, msg: "服务器错误: " + String(e) }))
			}
		})
}

// 自签名证书：不存在则用 openssl 现场生成（10 年期，SAN 绑公网 IP；浏览器/手机各点一次"继续访问"即可）
function ensureCert() {
	if (fs.existsSync(CERT_FILE) && fs.existsSync(KEY_FILE)) return true
	const r = spawnSync("openssl", [
		"req", "-x509", "-newkey", "rsa:2048",
		"-keyout", KEY_FILE, "-out", CERT_FILE,
		"-days", "3650", "-nodes",
		"-subj", "/CN=dazhanggui",
		"-addext", "subjectAltName=IP:106.14.118.158",
	], { stdio: "ignore" })
	return r.status === 0
}

function startServer() {
	fs.mkdirSync(DATA_DIR, { recursive: true })
	for (const t of TABLES) loadTable(t)
	http.createServer(handleRequest).listen(PORT, function () {
		console.log("大掌柜云存档服务已启动(HTTP):  http://0.0.0.0:" + PORT)
	})
	if (ensureCert()) {
		var opts = { key: fs.readFileSync(KEY_FILE), cert: fs.readFileSync(CERT_FILE) }
		https.createServer(opts, handleRequest).listen(HTTPS_PORT, function () {
			console.log("大掌柜云存档服务已启动(HTTPS自签名): https://0.0.0.0:" + HTTPS_PORT)
		})
	} else {
		console.log("openssl 不可用，仅启动 HTTP；手机网页测试需要 HTTPS，请先 apt install openssl")
	}
}

startServer()
