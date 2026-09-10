# ============================================================
# 网络层（弱联网·云存档）：对接 Cloudflare Worker，注册/登录/上传/下载
# 定位：纯存储转发，服务端不做数值校验（朋友间自娱自乐，开挂随意）
# 令牌持久化在 user://net_auth.json，登录一次长期有效（服务端会话30天）
# 部署 Worker 后把 API_BASE 换成你的地址
# ============================================================
class_name NetSystem
extends Node

# 【改】部署后填入你的 Worker 地址（https://dazhanggui-save.<你的子域>.workers.dev）
const API_BASE := "https://dazhanggui-save.dazhanggui.workers.dev"

var username: String = ""
var token: String = ""
signal auth_expired()                 # 【新增】令牌被服务端判失效（401）：已清本地令牌，请玩家重新登录

signal login_result(ok: bool, msg: String)                 # 登录/注册结果（msg 为失败原因或成功提示）
signal upload_result(ok: bool)                             # 存档上传结果（静默处理，UI不强制消费）
signal download_result(ok: bool, has_save: bool, save_text: String, updated_at: int)   # 存档下载结果

func _ready():
	_load_auth()

# ============ 本地令牌持久化（user://net_auth.json） ============
func _auth_path() -> String:
	return "user://net_auth.json"

func _load_auth():
	if not FileAccess.file_exists(_auth_path()): return
	var f = FileAccess.open(_auth_path(), FileAccess.READ)
	if not f: return
	var j = JSON.new()
	if j.parse(f.get_as_text()) == OK:
		var d = j.get_data()
		if d is Dictionary:
			username = d.get("username", "")
			token = d.get("token", "")
	f.close()

func save_auth():
	var f = FileAccess.open(_auth_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"username": username, "token": token}))
		f.close()

func clear_auth():
	username = ""
	token = ""
	if FileAccess.file_exists(_auth_path()):
		DirAccess.remove_absolute(_auth_path())

# ============ 统一请求封装 ============
# path: 接口路径；payload: POST 体（空字典走 GET）；cb(code, parsed_dict)
func _request(path: String, payload: Dictionary, cb: Callable, use_auth := true):
	var req = HTTPRequest.new()
	req.timeout = 10   # 【修】默认无超时：workers.dev 国内不稳，被静默掐断时会永久挂起；10秒无响应即失败回调
	add_child(req)
	req.request_completed.connect(func(result, code, _headers, body):
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			cb.call(-1, {})
			return
		var j = JSON.new()
		if j.parse(body.get_string_from_utf8()) != OK:
			cb.call(code, {})
			return
		var d = j.get_data()
		cb.call(code, d if d is Dictionary else {})
	)
	var headers = ["Content-Type: application/json"]
	if use_auth and token != "":
		headers.append("Authorization: Bearer " + token)
	var err
	if payload.is_empty():
		err = req.request(API_BASE + path, headers, HTTPClient.METHOD_GET)
	else:
		err = req.request(API_BASE + path, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		req.queue_free()
		cb.call(-1, {})

# ============ 注册 / 登录 ============
# 【修】参数名 pass→pwd：pass 是 GDScript 保留关键字，不能用作参数名
func register(user: String, pwd: String):
	_request("/register", {"username": user, "password": pwd}, func(code, d):
		if code == 200 and d.get("ok", false):
			username = user
			token = d.get("token", "")
			save_auth()
			login_result.emit(true, "注册成功")
		else:
			var reason = d.get("msg", "网络错误(%d)" % code)
			if code == 409:
				reason += "，可直接登录或换个用户名"   # 【新增】撞已注册时给下一步指引，别只干巴巴一句
			login_result.emit(false, reason)
	, false)

func login(user: String, pwd: String):
	_request("/login", {"username": user, "password": pwd}, func(code, d):
		if code == 200 and d.get("ok", false):
			username = user
			token = d.get("token", "")
			save_auth()
			login_result.emit(true, "登录成功")
		else:
			login_result.emit(false, d.get("msg", "网络错误(%d)" % code))
	, false)

# ============ 存档上传 / 下载（后存覆盖先存） ============
func upload_save(save_text: String):
	if token == "" or save_text.is_empty(): return
	_request("/upload", {"save": save_text}, func(code, d):
		if code == 401:
			# 【新增】会话过期/令牌失效：立即清令牌并通知 UI——不清的话上传从此静默失败，
			# 玩家以为"自动同步着呢"实际永远没传上去（服务端会话 30 天，迟早踩到）
			clear_auth()
			auth_expired.emit()
			upload_result.emit(false)
			return
		if code == 200 and d.get("ok", false):
			upload_result.emit(true)
		else:
			upload_result.emit(false)
	)

func download_save():
	if token == "":
		download_result.emit(false, false, "", 0)
		return
	_request("/download", {}, func(code, d):
		if code == 401:
			# 【新增】同 upload：令牌失效清令牌+通知（启动仲裁过期=重新亮登录门）
			clear_auth()
			auth_expired.emit()
			download_result.emit(false, false, "", 0)
			return
		if code == 200 and d.get("ok", false):
			download_result.emit(true, d.get("has_save", false), d.get("save", ""), int(d.get("updated_at", 0)))
		else:
			download_result.emit(false, false, "", 0)
	)

# ============ 商会（guilds 表，后存覆盖先存，服务端不做数值校验） ============
# cb(code, dict)——与 _request 回调签名一致
func guild_create(p_name: String, cb: Callable):
	_request("/guild/create", {"name": p_name}, cb)

func guild_get(guild_id: String, cb: Callable):
	_request("/guild/get", {"guild_id": guild_id}, cb)

func guild_save(guild_id: String, record: Dictionary, cb: Callable):
	_request("/guild/save", {"guild_id": guild_id, "record": record}, cb)
