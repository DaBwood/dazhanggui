extends SceneTree

# ============================================================
# B2 原语单元测试：Accrual / RegenTimer / Clock
# 用法：godot --headless --path . --script res://tests/test_accrual_primitives.gd
# 只测纯函数边界，不建 GameData；系统级验收见 snapshot_accrual.gd。
# ============================================================

var _failed := false
var _exit_code := 0
var _ready_to_quit := false


func _initialize() -> void:
	_test_accrual()
	_test_units_from_seconds()
	_test_regen_apply()
	_test_regen_next()
	_test_clock()

	if _failed:
		printerr("##PRIM-FAIL##")
		_exit_code = 1
	else:
		print("##PRIM-OK##")
		_exit_code = 0
	_ready_to_quit = true


func _process(_delta: float) -> bool:
	if not _ready_to_quit:
		return false
	quit(_exit_code)
	return true


func _test_accrual() -> void:
	_expect_f(Accrual.elapsed_units(0, 1000, 60.0), 0.0, "未初始化返回 0")
	_expect_f(Accrual.elapsed_units(1000, 1000, 60.0), 0.0, "同一 now 返回 0")
	_expect_f(Accrual.elapsed_units(1000, 4600, 60.0), 60.0, "+1h 折 60 分钟")
	_expect_f(Accrual.elapsed_units(4600, 1000, 60.0), 0.0, "回拨按 0")
	_expect_f(Accrual.elapsed_units(1000, 4600, 60.0, 0.0), 60.0, "cap=0 不封顶")
	_expect_f(Accrual.elapsed_units(1000, 4600, 60.0, 30.0), 30.0, "cap=30 分钟截断")
	_expect_f(Accrual.elapsed_units(1000, 1000 + 121 * 3600, 60.0, 120.0 * 60.0), 7200.0, "+121h 按 120h 封顶")
	# 幂等：纯函数，同参两次同值
	var a: float = Accrual.elapsed_units(1000, 4600, 60.0, 30.0)
	var b: float = Accrual.elapsed_units(1000, 4600, 60.0, 30.0)
	_expect_f(a, b, "同参两次同值")


func _test_units_from_seconds() -> void:
	_expect_f(Accrual.units_from_seconds(3600, 60.0), 60.0, "3600 秒折 60 分钟")
	_expect_f(Accrual.units_from_seconds(48 * 3600, 60.0, 24.0 * 60.0), 1440.0, "48h 按 24h 封顶")
	_expect_f(Accrual.units_from_seconds(-5, 60.0), 0.0, "负秒数按 0")


func _test_regen_apply() -> void:
	_expect_a(RegenTimer.apply(0, 1000, 1000, 1200, 50), [0, 1000], "同一 now 不变")
	_expect_a(RegenTimer.apply(0, 1000, 2200, 1200, 50), [1, 2200], "+1 间隔")
	_expect_a(RegenTimer.apply(1, 2200, 2800, 1200, 50), [1, 2200], "半间隔保留余数")
	_expect_a(RegenTimer.apply(1, 2200, 3400, 1200, 50), [2, 3400], "余数累积后再 +1")
	_expect_a(RegenTimer.apply(49, 1000, 1000 + 5 * 1200, 1200, 50), [50, 7000], "封顶")
	_expect_a(RegenTimer.apply(54, 1000, 2200, 1200, 50), [50, 2200], "超上限后自然恢复回落")
	_expect_a(RegenTimer.apply(10, 1000, 500, 1200, 50), [10, 1000], "回拨不变")
	_expect_a(RegenTimer.apply(10, 1000, 2000, 0, 50), [10, 1000], "interval=0 不崩")


func _test_regen_next() -> void:
	_expect_i(RegenTimer.next_seconds(1000, 1000, 1200), 1200, "刚恢复完 = 整间隔")
	_expect_i(RegenTimer.next_seconds(1000, 1600, 1200), 600, "半间隔 = 600")
	_expect_i(RegenTimer.next_seconds(1000, 2200, 1200), 0, "刚好到点 = 0")
	_expect_i(RegenTimer.next_seconds(1000, 2800, 1200), -600, "过点返回负数，由调用方夹 0")


func _test_clock() -> void:
	Clock.override_now = 12345
	_expect_i(Clock.now(), 12345, "假时钟覆盖")
	Clock.override_now = -1
	_expect_b(Clock.now() > 1000000000, "恢复系统时间")


# ============================================================
# 断言
# ============================================================

func _expect_f(got: float, want: float, label: String) -> void:
	if not is_equal_approx(got, want):
		push_error("[PRIM] %s：got=%.17f want=%.17f" % [label, got, want])
		_failed = true


func _expect_i(got: int, want: int, label: String) -> void:
	if got != want:
		push_error("[PRIM] %s：got=%d want=%d" % [label, got, want])
		_failed = true


func _expect_b(cond: bool, label: String) -> void:
	if not cond:
		push_error("[PRIM] " + label)
		_failed = true


func _expect_a(got: Array, want: Array, label: String) -> void:
	if got.size() != want.size():
		push_error("[PRIM] %s：size %d != %d" % [label, got.size(), want.size()])
		_failed = true
		return
	for i in range(got.size()):
		if int(got[i]) != int(want[i]):
			push_error("[PRIM] %s：第 %d 项 got=%s want=%s" % [label, i, str(got[i]), str(want[i])])
			_failed = true
