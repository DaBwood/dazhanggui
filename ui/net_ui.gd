# ============================================================
# 《大掌柜》网络/登录/云存档 UI 块（2026-09-19 架构重构批次A，自 game_controller.gd 原样迁出）
# 职责：登录门 / 离线进入 / 同步遮罩 / 登录弹窗（含 Web HTML 表单）/ 云存档下载仲裁 /
#       存档冲突恢复弹窗 / 对账失败弹窗 / 账号面板 / 令牌失效处理 / 存档自动上传
# 约定：
#   · 本类是 RefCounted 不是 Node——一切节点树操作（has_node/get_node/add_child/remove_child/
#     get_node_or_null/get_tree）必须经 c 转发；弹窗/遮罩挂 c 根节点，z 序才对兄弟节点有效；
#   · 对 controller 其它设施（data/net/弹窗工厂/飘字/_safe_close 等）一律 c.xxx；
#   · 块内互调（本文件的函数之间）直接本地调用，不加 c. 前缀。
# ============================================================
class_name NetUi
extends RefCounted

var c   # game_controller 根脚本（无类型，与 pages 模块一致；c.data=中枢 c.net=网络层）

var _web_login_cb = null          # 【新增】Web 登录表单 JS 回调引用（JavaScriptBridge 回调是 RefCounted，必须持有否则被释放后回调失效）
var _manual_download := false     # 【新增】标记本次下载是手动触发（恢复按钮），用于给提示
var _net_login_pending := false   # 【新增】登录流程中：正等云端存档查询结果来决定用哪份档

func _init(p_c):
	c = p_c

# 【新增】登录门：全屏遮罩挡住游戏，必须先登录/注册（或离线模式）才能进游戏
func _show_login_gate():
	if c.has_node("LoginGate"): return
	var gate = ColorRect.new()
	gate.name = "LoginGate"
	gate.color = Color(0.09, 0.08, 0.16, 1)
	gate.set_anchors_preset(Control.PRESET_FULL_RECT)
	gate.z_index = 90
	c.add_child(gate)
	var vb = VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.position = Vector2(-110, -190)
	vb.add_theme_constant_override("separation", 16)
	gate.add_child(vb)
	var hint = Label.new()
	hint.text = "登录或注册后进入游戏\n存档跟随账号"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)
	var offline = Button.new()
	offline.text = "离线模式（不联机）"
	offline.pressed.connect(_enter_offline)
	vb.add_child(offline)

	# 【新增】令牌有效→免密快捷进入行（点"进入游戏"才走对账；对账失败会被 SyncFailPopup 拦在门口）
	if c.net != null and c.net.token != "":
		var row = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 16)
		vb.add_child(row)
		var who = Label.new()
		who.text = "当前账号：" + c.net.username
		who.add_theme_color_override("font_color", Color(0.91, 0.78, 0.42))
		row.add_child(who)
		var quick = Button.new()
		quick.text = "进入游戏"
		quick.custom_minimum_size = Vector2(140, 44)
		quick.pressed.connect(func():
			if c.has_node("LoginGate"):
				var gate_node = c.get_node("LoginGate")
				c.remove_child(gate_node)
				gate_node.queue_free()
			c.data.set_save_path_for(c.net.username)
			_net_login_pending = true
			_show_sync_mask()
			c.net.download_save()
		)
		row.add_child(quick)
		var switch_btn = Button.new()
		switch_btn.text = "切换账号"
		switch_btn.custom_minimum_size = Vector2(110, 44)
		switch_btn.pressed.connect(func():
			c.net.clear_auth()
			c.get_tree().reload_current_scene()
		)
		row.add_child(switch_btn)
	else:
		_show_login_popup()

# 【新增】离线模式进游戏：不登录，用默认本地档，不与云端同步（云连不上时的保底入口）
func _enter_offline():
	c._safe_close("LoginPopup")
	if c.has_node("LoginGate"):
		var gate = c.get_node("LoginGate")
		c.remove_child(gate)
		gate.queue_free()
	c._enter_game()

# 【新增】同步遮罩：登录后到云端仲裁完成前，挡住"拆门了但游戏还没进"的空白期
# （workers.dev 国内不稳，download 最长 10 秒超时才回调；遮罩在 _enter_game 开头统一摘）
func _show_sync_mask():
	if c.has_node("SyncMask"): return
	var mask = ColorRect.new()
	mask.name = "SyncMask"
	mask.color = Color(0.09, 0.08, 0.16, 1)
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.z_index = 88
	c.add_child(mask)
	var lbl = Label.new()
	lbl.text = "正在同步存档…"
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.position = Vector2(-50, -10)
	mask.add_child(lbl)

func _hide_sync_mask():
	if c.has_node("SyncMask"):
		var mask = c.get_node("SyncMask")
		c.remove_child(mask)
		mask.queue_free()

# 【新增】令牌失效（401）处理：net 已清本地令牌。游戏中→提示重启重登；
# 还没进游戏（启动仲裁过期）→重新亮登录门走正常登录
func _on_net_auth_expired():
	if c._game_entered:
		c._show_stage_hint("登录已过期，云端同步已停止，重启游戏后重新登录", 5.0)
	else:
		_show_login_gate()

# 【新增】本地存档写盘 → 自动上传云端（未登录静默跳过；上传失败不打扰，下次自动存再传）
func _on_game_saved_upload(save_text: String):
	if c.get_node_or_null("CloudRestorePopup") != null:
		return   # 存档弹窗开着：暂停上传，等玩家选完/点完
	if c.net != null and c.net.token != "":
		c.net.upload_save(save_text)

# 【新增】登录/注册结果：成功→拆登录门、档随账号→进游戏；失败把原因写回状态行
func _on_net_login_result(ok: bool, msg: String):
	# 【改】Web 表单收尾：成功→JS 删表单；失败→JS 恢复按钮并把原因写进表单状态行（表单已独立成卡）
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__dzg_login_finish && window.__dzg_login_finish(" + ("true" if ok else "false") + "," + JSON.stringify(msg) + ")", true)
	var popup = c.get_node_or_null("LoginPopup")
	if popup:
		var status = popup.find_child("StatusLabel", true, false)
		if status: status.text = msg
	if not ok:
		# 【新增】防连点：登录/注册失败恢复按钮，允许改了再试
		if popup:
			for btn_name in ["LoginBtn", "RegBtn"]:
				var b = popup.find_child(btn_name, true, false)
				if b: b.disabled = false
		return
	c._safe_close("LoginPopup")
	if c.has_node("LoginGate"):
		var gate = c.get_node("LoginGate")
		c.remove_child(gate)
		gate.queue_free()
	# 档随账号：切换存档路径（首次登录自动迁移旧默认档保底）
	c.data.set_save_path_for(c.net.username)
	# 登录成功后一律拉云端存档仲裁，不再只看本机有没有档——set_save_path_for 的迁移
	# 会把 save.json 复制成账号档使 file_exists 恒真，据此跳过云端查询，"迁移来的别的档"就会静默盖掉云端
	_net_login_pending = true   # 等仲裁结果决定用哪份档、何时进游戏（登录只发生在登录门，中途登录入口已封）
	_show_sync_mask()           # 【新增】拆门后到仲裁完成前挡空白
	c.net.download_save()

# 【新增】下载结果统一处理：登录门仲裁 / 启动自动登录仲裁 / 游戏中途登录冲突 / 手动恢复 共用一个入口
func _on_net_download_result(ok: bool, has_save: bool, save_text: String, updated_at: int):
	var was_manual = _manual_download
	_manual_download = false
	# 登录门/自动登录的统一下载仲裁：本地档与云端档可能是不同血缘（换账号、旧档残留），
	# 必须先对比再决定用哪份档，杜绝"本地较新就静默盖云端"
	if _net_login_pending:
		_net_login_pending = false
		# 【新增】拉取失败绝不静默进游戏（2026-09-08丢档事故根因）：空档进游戏30秒后自动上传，
		# 会把云端好档顶掉。网络错误(令牌仍有效)→弹窗选 重试/显式离线进入；401(令牌已清)→回登录门
		if not ok:
			if c.net.token != "":
				_show_sync_fail_popup()
			else:
				_show_login_gate()
			return
		if not has_save or save_text.is_empty():
			c._enter_game()   # 云端确认无档：本地（或新档）直接进，安全（玩家已在门后显式点过进入）
			return

		var info = _read_local_save_info()
		if not info.exists:
			# 本机无档：云端落盘直接用（原 pending 行为）
			var f0 = FileAccess.open(c.data.save_path, FileAccess.WRITE)
			if f0:
				f0.store_string(save_text)
				f0.close()
			c._enter_game()
			return
		var cloud_save_id := ""
		var parsed = JSON.parse_string(save_text)
		if parsed is Dictionary:
			cloud_save_id = str(parsed.get("save_id", ""))
		if cloud_save_id == "" or cloud_save_id != info.save_id:
			# 血缘不同（或云端旧档缺ID无法判定）：先进游戏（本地档），弹窗让玩家选；选恢复云端则写档重载
			c._enter_game()
			_show_cloud_restore_popup(save_text, updated_at)
			return
		# 同一血缘：新的那份赢，无需弹窗
		if updated_at / 1000.0 > info.last_logout + 5:
			var f1 = FileAccess.open(c.data.save_path, FileAccess.WRITE)
			if f1:
				f1.store_string(save_text)
				f1.close()
		c._enter_game()
		return
	if not ok:
		if was_manual: c._show_stage_hint("网络错误，稍后再试", 3.0)
		return
	if not has_save or save_text.is_empty():
		if was_manual: c._show_stage_hint("云端还没有存档", 3.0)
		return
	var manual_save_id := ""
	var parsed_manual = JSON.parse_string(save_text)
	if parsed_manual is Dictionary:
		manual_save_id = str(parsed_manual.get("save_id", ""))
	if manual_save_id == "" or manual_save_id != c.data.save_id:
		_show_cloud_restore_popup(save_text, updated_at)
		return
	if updated_at / 1000.0 <= c.data.last_logout_time + 5:
		if was_manual: c._show_stage_hint("云端存档不比本机新，无需恢复", 3.0)
		return
	# 云端较新（或手动"从云端恢复"）：统一走冲突/恢复弹窗（写明双方名字+时间，恢复写当前账号档）
	_show_cloud_restore_popup(save_text, updated_at)

# 【新增】对账失败弹窗：停在门口（盖过同步遮罩），绝不静默带空档进游戏。
# 重试=重新走下载仲裁；离线进入=玩家知悉"本地档将自动上传覆盖云端"风险后的显式选择
func _show_sync_fail_popup():
	if c.has_node("SyncFailPopup"): return
	var popup = c._create_base_popup("云端同步失败", Vector2(480, 280))
	popup.name = "SyncFailPopup"
	popup.z_index = 95   # 必须盖过 SyncMask(88) 与 LoginGate(90)
	c.add_child(popup)
	var vb = popup.get_child(0)
	var lbl = Label.new()
	lbl.text = "连不上云端存档服务器（网络不通）。\n\n直接进游戏将以本地存档开始，\n之后每次自动存档都会上传并覆盖云端旧档！"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	vb.add_child(row)
	var retry = Button.new()
	retry.text = "重试"
	retry.custom_minimum_size = Vector2(140, 44)
	retry.pressed.connect(func():
		c._safe_close("SyncFailPopup")
		_net_login_pending = true
		_show_sync_mask()
		c.net.download_save()
	)
	row.add_child(retry)
	var enter = Button.new()
	enter.text = "离线进入（本地优先）"
	enter.custom_minimum_size = Vector2(200, 44)
	enter.pressed.connect(func():
		c._safe_close("SyncFailPopup")
		c._enter_game()
	)
	row.add_child(enter)

# 【新增】读取本地存档的仲裁信息：存在性/血缘ID/下线时间。登录仲裁必须在 load_game 之前调用
# （此刻内存里的 last_logout_time 还是旧值/零，不代表本地档的真实时间，所以直接读文件）
func _read_local_save_info() -> Dictionary:
	var info := {"exists": false, "save_id": "", "last_logout": 0.0}
	var f = FileAccess.open(c.data.save_path, FileAccess.READ)
	if f == null:
		return info
	var text = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		info.exists = true
		info.save_id = str(parsed.get("save_id", ""))
		info.last_logout = float(parsed.get("last_logout_time", 0))
	return info

# 【改】存档冲突询问：摆出云端/本地双方名字与保存时间，按钮标明谁覆盖谁；
#       确认恢复写当前账号档 data.save_path（原来误写常量 SAVE_PATH=save.json，恢复会写错文件）
func _show_cloud_restore_popup(save_text: String, updated_at: int):
	c._safe_close("CloudRestorePopup")
	var popup = c._create_base_popup("存档冲突", Vector2(480, 280))
	popup.name = "CloudRestorePopup"
	popup.z_index = 30   # 弹窗层
	c.add_child(popup)   # 【修】补上挂树：原实现漏这行，面板永不出现、55% 遮罩残留全屏挡死（2026-09-19 实锤修复）
	var vb = popup.get_child(0)
	# 【新增】解析云端档里的角色名，和本地并排展示——玩家看得见两边是什么档再选
	var cloud_name := "?"
	var parsed = JSON.parse_string(save_text)
	if parsed is Dictionary:
		cloud_name = str(parsed.get("player_name", "?"))
	var lbl = Label.new()
	# 【修】Godot 的 get_datetime_string_from_unix_time 第二参是 use_space 不是时区，输出 UTC 慢 8 小时——
	# 手动 +8h 对齐中国时区；两边同加，相对比较不受影响
	lbl.text = "云端存档「%s」保存于 %s\n本地「%s」保存于 %s\n要保留哪一个？" % [
		cloud_name,
		Time.get_datetime_string_from_unix_time(int(updated_at / 1000.0) + 8 * 3600, true),
		c.data.player_name,
		Time.get_datetime_string_from_unix_time(int(c.data.last_logout_time) + 8 * 3600, true),
	]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	vb.add_child(row)
	var confirm = Button.new()
	confirm.text = "恢复云端（覆盖本地）"
	confirm.custom_minimum_size = Vector2(180, 44)
	confirm.pressed.connect(func():
		# 【改】写当前账号档（原来写 data.SAVE_PATH 常量，恢复的档会进错文件）
		var f = FileAccess.open(c.data.save_path, FileAccess.WRITE)
		if f:
			f.store_string(save_text)
			f.close()
		c.get_tree().reload_current_scene()
	)
	row.add_child(confirm)
	var cancel = Button.new()
	cancel.text = "保留本地（覆盖云端）"
	cancel.custom_minimum_size = Vector2(180, 44)
	cancel.pressed.connect(func(): c._safe_close("CloudRestorePopup"))
	row.add_child(cancel)

func _on_account_btn_pressed():
	# 【改】离线模式（无令牌）不再提供中途登录入口——旧链路"离线→中途登录→云端覆盖本地"
	# 屡修不稳，产品原则改为：想登录只能「退出」返回登录门走登录页（见 _on_exit_confirmed 离线分支）。
	# 离线模式本身是开发期测试口子，发布前整个移除
	if c.net.token == "":
		c._safe_close("OfflineHintPopup")
		var hint = c._create_base_popup("离线模式", Vector2(420, 200))
		hint.name = "OfflineHintPopup"
		hint.z_index = 30
		c.add_child(hint)
		var vb = hint.get_child(0)
		var lbl = Label.new()
		lbl.text = "离线模式无法登录\n如需使用云存档，请点「退出」返回登录页面后再登录"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(lbl)
		c._add_ok_button(vb, func(): c._safe_close("OfflineHintPopup"), "知道了")
		return
	_show_account_panel()

# 【新增】账号面板：当前账号/立即同步/从云端恢复/退出登录
func _show_account_panel():
	c._safe_close("AccountPanel")
	var popup = c._create_base_popup("账号", Vector2(420, 300))
	popup.name = "AccountPanel"
	popup.z_index = 30
	c.add_child(popup)
	var vb = popup.get_child(0)
	var lbl = Label.new()
	lbl.text = "当前账号：%s" % c.net.username
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl)
	var sync_btn = Button.new()
	sync_btn.text = "立即同步存档"
	sync_btn.custom_minimum_size = Vector2(180, 40)
	sync_btn.pressed.connect(func():
		c.data.save_game()   # 写盘同时经 game_saved 信号自动上传
		c._show_stage_hint("已同步到云端", 3.0)
	)
	vb.add_child(sync_btn)
	var dl_btn = Button.new()
	dl_btn.text = "从云端恢复"
	dl_btn.custom_minimum_size = Vector2(180, 40)
	dl_btn.pressed.connect(func():
		c._safe_close("AccountPanel")
		_manual_download = true
		c.net.download_save()
	)
	vb.add_child(dl_btn)
	var out_btn = Button.new()
	out_btn.text = "退出登录"
	out_btn.custom_minimum_size = Vector2(180, 40)
	out_btn.pressed.connect(func():
		c.data.save_game()                    # 退出前最后同步一次到云端
		c.net.clear_auth()
		c.get_tree().reload_current_scene()   # 重载场景=回到登录门（token已清，不会直接进游戏）
	)
	vb.add_child(out_btn)
	c._add_ok_button(vb, func(): c._safe_close("AccountPanel"), "关闭")

# 【新增】登录/注册弹窗：Web 端走 HTML 原生输入框（手机虚拟键盘引擎bug绕法，见档案踩坑11）；桌面/编辑器用 LineEdit
func _show_login_popup():
	c._safe_close("LoginPopup")
	if OS.has_feature("web"):
		_show_web_login_form()
		return
	var popup = c._create_base_popup("账号登录", Vector2(420, 320))
	popup.name = "LoginPopup"
	popup.z_index = 95
	c.add_child(popup)
	var vb = popup.get_child(0)
	var status = Label.new()
	status.name = "StatusLabel"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "登录后可云存档，换设备不丢进度"
	vb.add_child(status)
	var user_edit = LineEdit.new()
	user_edit.placeholder_text = "用户名"
	vb.add_child(user_edit)
	var pass_edit = LineEdit.new()
	pass_edit.placeholder_text = "密码"
	pass_edit.secret = true
	vb.add_child(pass_edit)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	var login_btn = Button.new()
	login_btn.name = "LoginBtn"
	login_btn.text = "登录"
	login_btn.custom_minimum_size = Vector2(110, 40)
	row.add_child(login_btn)
	var reg_btn = Button.new()
	reg_btn.name = "RegBtn"
	reg_btn.text = "注册"
	reg_btn.custom_minimum_size = Vector2(110, 40)
	row.add_child(reg_btn)
	# 【新增】防连点：按下即禁用两按钮；失败由 _on_net_login_result 恢复（成功则弹窗整个关掉）
	login_btn.pressed.connect(func():
		login_btn.disabled = true
		reg_btn.disabled = true
		c.net.login(user_edit.text.strip_edges(), pass_edit.text)
	)
	reg_btn.pressed.connect(func():
		login_btn.disabled = true
		reg_btn.disabled = true
		c.net.register(user_edit.text.strip_edges(), pass_edit.text)
	)
	var off_btn = Button.new()
	off_btn.text = "离线模式"
	off_btn.custom_minimum_size = Vector2(110, 40)
	off_btn.pressed.connect(_enter_offline)
	row.add_child(off_btn)

# 【新增】Web 登录表单：HTML 原生输入框居中悬浮（DOM 渲染，手机键盘正常调起）
func _show_web_login_form():
	if _web_login_cb == null:
		_web_login_cb = JavaScriptBridge.create_callback(_on_web_login_form_result)
	JavaScriptBridge.get_interface("window").__dzg_login_cb = _web_login_cb
	JavaScriptBridge.eval("""
		(function(){
			var old = document.getElementById('dzg-login');
			if (old) old.remove();
			var div = document.createElement('div');
			div.id = 'dzg-login';
			div.style.cssText = 'position:fixed;left:50%;top:42%;transform:translate(-50%,-50%);' +
				'z-index:999;background:#2a2640;border:2px solid #7a6fb0;border-radius:10px;' +
				'padding:18px;width:240px;text-align:center;';
			div.innerHTML =
				'<div style="color:#e8c66a;font-size:16px;margin-bottom:10px;">账号登录</div>' +
				'<div id="dzg-status" style="color:#c9bfa8;font-size:12px;min-height:18px;margin-bottom:10px;">登录后可云存档，换设备不丢进度</div>' +
				'<input id="dzg-user" placeholder="用户名" ' +
				'style="width:100%;box-sizing:border-box;margin-bottom:10px;padding:8px;border-radius:4px;border:1px solid #555;">' +
				'<input id="dzg-pass" type="password" placeholder="密码" ' +
				'style="width:100%;box-sizing:border-box;margin-bottom:12px;padding:8px;border-radius:4px;border:1px solid #555;">' +
				'<button style="margin:0 4px;padding:8px 16px;">登录</button>' +
				'<button style="margin:0 4px;padding:8px 16px;">注册</button>' +
				'<button style="margin:0 4px;padding:8px 16px;">取消</button>';
			var btns = div.getElementsByTagName('button');
			btns[0].onclick = function(){ window.__dzg_login_do('login'); };
			btns[1].onclick = function(){ window.__dzg_login_do('register'); };
			btns[2].onclick = function(){ window.__dzg_login_do('cancel'); };
			document.body.appendChild(div);
			// 提交：禁用按钮防连点，状态行显示"请求中"（结果回来前表单不删）
			window.__dzg_login_do = function(mode){
				var d = document.getElementById('dzg-login');
				if (mode === 'cancel') {   // 取消仍即删表单走离线
					if (d) d.remove();
					window.__dzg_login_cb(mode, '', '');
					return;
				}
				var bs = d.getElementsByTagName('button');
				for (var i = 0; i < bs.length; i++) bs[i].disabled = true;
				var st = document.getElementById('dzg-status');
				if (st) st.textContent = '请求中…';
				var u = d.querySelector('#dzg-user').value.trim();
				var p = d.querySelector('#dzg-pass').value;
				window.__dzg_login_cb(mode, u, p);
			};
			// Godot 结果回调：成功→删表单进游戏；失败→恢复按钮+状态行显示原因，用户名密码原样保留直接改着重试
			window.__dzg_login_finish = function(ok, msg){
				var d = document.getElementById('dzg-login');
				if (!d) return;
				if (ok) { d.remove(); return; }
				var bs = d.getElementsByTagName('button');
				for (var i = 0; i < bs.length; i++) bs[i].disabled = false;
				var st = document.getElementById('dzg-status');
				if (st) st.textContent = msg || '请求失败';
			};
		})()
	""", true)

# 【新增】HTML 登录表单回调（JS → GDScript）：args = [mode, 用户名, 密码]
func _on_web_login_form_result(args):
	var mode = str(args[0])
	if mode == "cancel":
		_enter_offline()   # 【改】取消=离线模式进游戏（不再记录跳过）
		return
	if mode == "login":
		c.net.login(str(args[1]), str(args[2]))
	elif mode == "register":
		c.net.register(str(args[1]), str(args[2]))
