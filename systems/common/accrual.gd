# ============================================================
# 连续时间窗（B2 收益罐原语）
# 只负责「上次时间戳 → now」折算成单位数（分钟/秒）并按上限截断；
# 产出公式仍留在各系统里，保证浮点运算次序与重构前逐位一致。
# 不读系统时间：now 一律由调用方传入，测试可注入假时钟。
# ============================================================
class_name Accrual
extends RefCounted

# 返回 [0, ∞) 的单位数。last_ts <= 0 视为未初始化，返回 0。
# cap_units <= 0 表示不封顶（与交接稿的 cap_seconds == 0 同义）。
static func elapsed_units(last_ts: int, now: int, unit_seconds: float, cap_units: float = 0.0) -> float:
	if last_ts <= 0 or unit_seconds <= 0.0:
		return 0.0
	var units: float = maxf(0.0, (float(now) - float(last_ts)) / unit_seconds)
	if cap_units > 0.0:
		units = minf(units, cap_units)
	return units

# 已算好秒数的入口（离线结算）：先折算单位，再按上限截断。
static func units_from_seconds(seconds: int, unit_seconds: float, cap_units: float = 0.0) -> float:
	if unit_seconds <= 0.0:
		return 0.0
	var units: float = maxf(0.0, float(seconds) / unit_seconds)
	if cap_units > 0.0:
		units = minf(units, cap_units)
	return units
