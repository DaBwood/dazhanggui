# ============================================================
# 可注入时钟（B2 测试钩子）
# 游戏运行时 override_now = -1，行为与 int(Time.get_unix_time_from_system()) 完全一致。
# 测试脚本设置 override_now 后，被迁移系统的时间读取全部走假时钟。
# ============================================================
class_name Clock
extends RefCounted

static var override_now: int = -1

static func now() -> int:
	if override_now >= 0:
		return override_now
	return int(Time.get_unix_time_from_system())
