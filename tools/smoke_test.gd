# ============================================================
# tools/smoke_test.gd —— 无头冒烟测试（回归网）
#
# 用途：本项目 2MB GDScript、每月大量改动，却没有自动化回归手段。
#      本脚本把"最容易被搬结构搬坏"的路径全跑一遍：进游戏 → 5 个主页面 →
#      VIEW_LIST 里每个子视图的开/关 → 全量刷新。任何节点路径写错、空引用、
#      方法改名，都会在 stderr 打出 ERROR / SCRIPT ERROR。
#
# 用法（项目根目录，Godot 可执行文件换成你自己的路径）：
#   godot --headless --path . --script res://tools/smoke_test.gd 2>&1 | tee smoke.log
#   # 然后搜 smoke.log 里的 "ERROR" / "[视图] 方法缺失"：有输出就是要看的
#
# 注意：
#   - 无头模式不渲染，所以它查不出"位置/颜色不对"，只查逻辑与节点路径。
#   - 会在 user:// 写一份测试存档（正常游戏存档路径），介意的话先备份。
#   - 退出码 0 = 跑完；报错信息看 stderr，不是退出码。
# ============================================================
extends SceneTree

# 这几类视图按设计不走 show_view() 通用入口（见 game_controller.VIEW_LIST 注释）：
# courtyard = 庄园页签内容；costume/soul/soulpower = 由页面直调各自 show_xxx_popup；
# fish_equip = 需要门客参数（show_view(key, [参数])）
const SKIP_KEYS := ["courtyard", "costume", "soul", "soulpower", "fish_equip"]
const MAIN_PAGES := ["mansion", "shop", "hero", "adventure", "bag"]

var c: Node
var steps: Array = []
var frame := 0
var done := 0
var failed: Array = []

func _initialize() -> void:
	var ps: PackedScene = load("res://control.tscn")
	if ps == null:
		push_error("[冒烟] control.tscn 加载失败")
		quit(1)
		return
	c = ps.instantiate()
	root.add_child(c)
	print("[冒烟] 主场景已实例化")

func _process(_d: float) -> bool:
	frame += 1
	if frame == 3:
		print("[冒烟] ===== 进入游戏 =====")
		c._enter_game()
		_build_steps()
		return false
	if frame < 5:
		return false
	if steps.is_empty():
		print("[冒烟] ===== 跑完 %d 步 =====" % done)
		print("[冒烟] 上面若出现 ERROR / SCRIPT ERROR / [视图] 方法缺失，就是要修的点")
		return true
	var s: Array = steps.pop_front()
	_run(s)
	return false

func _build_steps() -> void:
	for p in MAIN_PAGES:
		steps.append(["page", p])
	if "VIEW_LIST" in c:
		for e in c.VIEW_LIST:
			var key := str(e.get("key", ""))
			if key in SKIP_KEYS:
				continue
			steps.append(["view_open", key])
			steps.append(["view_close", key])
	for f in ["open_mall_panel", "open_player_panel", "update_all_ui"]:
		if c.has_method(f):
			steps.append(["call", f])

func _run(s: Array) -> void:
	var label: String = s[0] + ":" + str(s[1])
	print("[冒烟] >>> ", label)
	match s[0]:
		"page":
			c.switch_page(s[1])
		"view_open":
			c.show_view(s[1])
		"view_close":
			c.hide_view(s[1])
		"call":
			c.call(s[1])
	done += 1
