# ============================================================
# BaseView 视图公共基类（2026-09-18 架构重构批次③）
# 六个玩法视图（winery/drugshop/tavern/clinic/inn/bank）逐批迁移到本基类，
# 公约数全部下沉到此，各视图只留：_build 内容 + 弹窗工厂 + 业务回调。
# 已下沉的公共件（子类不要再自写）：
#   c/data 引用注入、_close_node、全屏页 show_view/hide_view、
#   弹窗状态机（_popup_kind/_popup_id）、close_popup、_refresh 重建、_add_btn_dot 红点
# 子类约定：
#   _init(p_c) 第一行 super(p_c)，随后赋 _page_name/_popup_node_name/_page_bg
#   实现 _build(page: Panel) 构建页面内容
#   弹窗视图按需实现 _rebuild_popup()：按 _popup_kind/_popup_id 分发重建
#   保留 show_<key>_view()/hide_<key>_view() 薄封装（controller VIEW_LIST 的 key 命名约定）
# ⚠️ 生命周期特殊者（如 tavern 页内 Timer/进出复位）可整体重写 show_view/hide_view
# ============================================================
class_name BaseView
extends RefCounted

var c      # game_controller 根脚本引用
var data: GameData   # 数据中枢（显式标注 GameData：中枢字段被静态引用，消 UNUSED 提示）

# ---- 页面身份（子类 _init 里赋值）----
var _page_name: String = ""          # 页面节点名（挂 c 根，如 "WineryPage"）
var _popup_node_name: String = ""    # 弹窗节点名（弹窗工厂建 PanelContainer 时同名，如 "WineryPopup"）
var _page_bg: String = "#1e1b2e"     # 全屏页底色（无素材期代码配色，默认深紫底）

# ---- 弹窗状态机（子类弹窗工厂负责赋值；hide/close 时由基类清零）----
var _popup_kind: String = ""     # 当前弹窗类别（""=无）
var _popup_id: String = ""       # 当前弹窗对应业务 id（按 kind 语义）

func _init(p_c):
	c = p_c
	data = p_c.data

# 按名关闭并销毁挂在 c 根上的节点（纯关不报错；但游离节点不挂树不报错只隐身——协作踩坑 8，必须显式清）
func _close_node(node_name: String):
	var n = c.get_node_or_null(node_name)
	if n:
		c.remove_child(n)
		n.queue_free()

# 打开全屏页：关旧页+关弹窗（不动弹窗状态，_refresh 重建依赖这点）→ 建 Panel(z35) 铺满 → _build
func show_view():
	_close_node(_page_name)
	_close_node(_popup_node_name)
	var page := Panel.new()
	page.name = _page_name
	page.z_index = 35   # 全屏页 z 总表：35（档案三-36）
	page.position = Vector2.ZERO
	page.size = c.get_viewport_rect().size
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(_page_bg)
	page.add_theme_stylebox_override("panel", bg)
	c.add_child(page)
	_build(page)
	_after_build(page)   # 子类可选钩子：挂 Timer 等页面级附件（drugshop/tavern 用）

# 关闭全屏页：清弹窗状态 + 关页面 + 关弹窗
func hide_view():
	_popup_kind = ""
	_popup_id = ""
	_close_node(_page_name)
	_close_node(_popup_node_name)

# 关闭弹窗：清状态 + 关弹窗节点（原各视图 _close_popup 同款）
func close_popup():
	_popup_kind = ""
	_popup_id = ""
	_close_node(_popup_node_name)

# 重建页面；弹窗状态非空则按状态重建弹窗（子类 _rebuild_popup 分发，winery 原 _refresh 惯例下沉）
func _refresh():
	_close_node(_page_name)
	show_view()
	if _popup_kind != "":
		_rebuild_popup()

# 子类按需重写：按 _popup_kind/_popup_id 分发重建弹窗（基类默认无弹窗可重建）
func _rebuild_popup():
	pass

# 子类必须实现：构建页面内容（page 为铺满视口的 z35 Panel）
@warning_ignore("unused_parameter")
func _build(page: Panel):
	pass

# 子类可选重写：_build 之后的页面级附件（如后台节拍 Timer 挂在 page 上随关页自动销毁）
@warning_ignore("unused_parameter")
func _after_build(page: Panel):
	pass

# 按钮右上角内部红点（锚定右上，不依赖节点尺寸；全玩法统一模板，红点一律页内展示不穿透地图）
func _add_btn_dot(btn: Button, cond: bool):
	var d := Label.new()
	d.text = "●"
	d.add_theme_color_override("font_color", Color("#e74c3c"))
	d.add_theme_font_size_override("font_size", 14)
	d.anchor_left = 1.0
	d.anchor_right = 1.0
	d.anchor_top = 0.0
	d.anchor_bottom = 0.0
	d.offset_left = -18
	d.offset_right = -2
	d.offset_top = 2
	d.offset_bottom = 18
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.visible = cond
	btn.add_child(d)
