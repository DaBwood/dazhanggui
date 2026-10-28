# ============================================================
# 离散恢复计时器（B2 原语）
# 每 interval 秒恢复 1 点，封顶 cap；余数保留在 ts 里（不清零）。
# 不持有状态：调用方把原字段传进来，结果再写回原字段，存档形状不变。
# ============================================================
class_name RegenTimer
extends RefCounted

# 返回 [new_value, new_ts]。gained <= 0 时原样返回。
static func apply(value: int, ts: int, now: int, interval: int, cap: int) -> Array:
	if interval <= 0:
		return [value, ts]
	var gained: int = int((now - ts) / float(interval))
	if gained <= 0:
		return [value, ts]
	return [mini(cap, value + gained), ts + gained * interval]

# 距下一点恢复的秒数（不夹 0；调用方按各自原口径决定是否 maxi）。
static func next_seconds(ts: int, now: int, interval: int) -> int:
	return interval - (now - ts)
