# 底座改造 · Kimi 交接

> 执行方：Kimi。验收方：DeepSeek（我）。
> 仓库：`C:\Users\林\Documents\大掌柜`，Godot 4.7.1，HEAD `d584beb`。
> 开工前必读：`AGENTS.md`（红线）、`docs/系统看板.md`（现状）。
> 本文件只做三件事：**定范围、定契约、定验收**。不要自由发挥。

---

## 0. 三条铁律

1. **不改行为。** 所有现有数值、存档字段、UI 布局、节点名保持不变。重构前后必须能读出同一份存档、算出同一组数。
2. **不改存档结构。** 不新增/重命名字段；老档直接能读。原语只接管计算，不接管落盘格式。
3. **不扩范围。** 每阶段只动「文件白名单」里的文件；想顺手改的，写进阶段报告，不写进代码。

违反任意一条，整阶段打回。

---

## 1. 为什么要做

现在 40 个系统各写一套「收益罐 / 勋章 / 页面壳」，并且商铺加成是 **14 项手写加法**：

- `systems/shop_system.gd:91-99` 一条 `1.0 + ...` 串起 14 个加成源；
- 第 100 行留着事故记录：新项误粘进注释尾部，整串加成静默失效（2026-10-06 实测）；
- 每加一个全局系统，都要回来改这一行 + `game_data` 转发。

底座的目标：**新系统只填配置 / 只写页面 body，不再改中心公式。**

---

## 2. 验收指标（总）

- 新增一个全局加成源：**只注册一行**，不改 `shop_system.gd`。
- 新增一个收益罐玩法：**只组合 `Accrual`**，不写时间戳结算。
- 新增一个 15 级勋章：**只给配置**，不写 level/claim/红点。
- 新增一个全屏页：**只写 body**，不写顶栏/返回/列表空态。
- 所有 golden 快照**逐字节一致**（整数完全相等，不做容差）。

---

## 3. 分支与交付格式

- 从 `d584beb` 开分支 `refactor/base-layer`。
- **每阶段一个 commit**，不 push。
- 每阶段在 `docs/底座-阶段报告.md` 追加一节：改了什么 / 没改什么 / 验证命令 / 结果 / 风险。
- 交付时给 `git diff --stat` 与三次 headless 输出，不贴整文件。
- 不 commit 提取产物（在工程外 `C:\Users\林\Documents\大掌柜_assets\`，不在仓库里）。

---

## 4. B1：Shop 加成注册表（0.5–1 天）

### 现状

`systems/shop_system.gd` 的 `get_shop_auto_income(shop_id)`：

```gdscript
var bonus = 1.0 + get_global_bonus_percent() + hero_bonus + friend_shop_bonus \
	+ g.get_courtyard_shop_percent_bonus(shop_id) \
	+ g.get_manor_shop_pct_bonus(str(s.get("category", ""))) \
	+ g.guild_system.get_career_bonus(str(s.get("category", ""))) \
	+ g.clinic_system.get_category_bonus(str(s.get("category", ""))) \
	+ g.drugshop_system.get_medal_shop_pct() + g.winery_system.get_medal_shop_pct() \
	+ g.winery_system.get_workshop_career_pct(str(s.get("category", ""))) \
	+ g.miaoyin_system.get_medal_shop_pct() \
	+ g.fishing_system.get_medal_shop_pct() \
	+ g.collection_system.get_medal_shop_pct() \
	+ g.xiangfang_system.get_medal_shop_pct()
```

### 设计

`game_data.gd` 新增（放在 `_register_hero_bonuses()` 旁边）：

```gdscript
var _shop_modifiers: Array = []   # [{label: String, fn: Callable}]

func clear_shop_modifiers() -> void:
	_shop_modifiers.clear()

func register_shop_modifier(label: String, fn: Callable) -> void:
	_shop_modifiers.append({"label": label, "fn": fn})

func get_shop_modifier_sum(shop_id: String) -> float:
	var s: Dictionary = shops.get(shop_id, {})
	var ctx := {"shop_id": shop_id, "category": str(s.get("category", ""))}
	var total := 0.0
	for m in _shop_modifiers:
		total += float(m.fn.call(self, ctx))
	return total
```

`shop_system.gd` 改成：

```gdscript
var bonus := 1.0 + g.get_shop_modifier_sum(shop_id)
```

保留所有原 getter，不改签名。

### 注册清单（顺序必须与现链完全一致）

顺序影响浮点求和结果，**不要按字母排序**。

| # | label | 现表达式 | 注册写法 |
|---|---|---|---|
| 1 | 钱庄 | `get_global_bonus_percent()` | `g.shop_system.get_global_bonus_percent()` |
| 2 | 门客派遣 | `hero_bonus` | `g.shop_system.get_assigned_hero_bonus(ctx.shop_id)`（把原循环抽成私有 helper） |
| 3 | 挚友 | `friend_shop_bonus` | `g.shop_system.get_assigned_friend_bonus(ctx.shop_id)`（同上） |
| 4 | 宅院 | `get_courtyard_shop_percent_bonus` | 直调，传 `ctx.shop_id` |
| 5 | 庄园 | `get_manor_shop_pct_bonus` | 直调，传 `ctx.category` |
| 6 | 商会 | `guild_system.get_career_bonus` | 直调 |
| 7 | 医馆 | `clinic_system.get_category_bonus` | 直调 |
| 8 | 药铺勋章 | `drugshop_system.get_medal_shop_pct` | 直调 |
| 9 | 酒坊勋章 | `winery_system.get_medal_shop_pct` | 直调 |
| 10 | 酒坊职业 | `winery_system.get_workshop_career_pct` | 直调 |
| 11 | 妙音坊勋章 | `miaoyin_system.get_medal_shop_pct` | 直调 |
| 12 | 垂钓勋章 | `fishing_system.get_medal_shop_pct` | 直调 |
| 13 | 藏品勋章 | `collection_system.get_medal_shop_pct` | 直调 |
| 14 | 厢房勋章 | `xiangfang_system.get_medal_shop_pct` | 直调 |

注册点：新函数 `_register_shop_bonuses()`，在 `_init` 里 `_register_hero_bonuses()` 之后调用。先 `clear_shop_modifiers()`，防重复。

### 数值快照（先写测试，再改代码）

新增 `tests/snapshot_economy.gd`（`extends SceneTree`），要求：

1. 用**公开 API** 构造 3 个 fixture，不手写存档字典：
   - **F1 新档**：默认状态。
   - **F2 中期**：`stage_main = 50`，解锁前 10 家店到 10 级，20 名门客 50 级、资质/技能若干，6 套勋章 5 级，VIP 5。
   - **F3 后期**：`stage_main = 100`，20 家店 20 级，全部门客 100 级，6 套勋章 15 级，VIP 16。
2. 输出稳定 JSON 到 stdout：
   ```json
   {"F1":{"shops":{"ke_zhan":123,...},"total":456,"heroes":{"hid":789,...}},"F2":{...},"F3":{...}}
   ```
   只输出**整数**，键按 `SHOP_ORDER` 排序。
3. 在 `d584beb` 上先跑一次，存 `tests/golden/economy_baseline.json`，commit 进分支。

改完后重跑，`git diff --exit-code tests/golden/economy_baseline.json` 必须无输出。

### 文件白名单

- `game_data.gd`
- `systems/shop_system.gd`
- `tests/snapshot_economy.gd`
- `tests/golden/economy_baseline.json`
- `docs/底座-阶段报告.md`

### 验收

- [ ] 快照逐字节一致（F1/F2/F3）
- [ ] `shop_system.gd` 不再含 14 项链
- [ ] 新增一个 dummy 加成只注册即生效（测试里注册一条 +1.0，总赚速按预期变化，撤销后复原）
- [ ] headless 退出码 0，无 `SCRIPT ERROR`
- [ ] `get_total_auto_income()` 单次 < 20ms（20 店 + 109 门客；超了就报告，不擅自加缓存）

### 回滚

`git revert` 该 commit；基线不动。B1 不过，不做 B2。

---

## 5. B2：Accrual 收益罐/队列原语（2–3 天）

> ⚠ **2026-10-28 已重划并完成。** 预检发现 `inn`/`tavern` 不是速率罐（客栈=批次作业、酒肆=恢复计时器+事件罐），
> 原映射表 `pending/pending_ts`、`jar/jar_ts` 与现码不符。
> 实际落地为双原语：`Accrual`（妙音坊/庄园）+ `RegenTimer`（酒肆/医馆/药铺）；
> 本节以下原文保留作历史记录，**执行口径以 [底座-阶段报告](底座-阶段报告.md) 的 B2 节为准**。

### 现状

7 套各自实现的时间戳结算：客栈（收益罐）、酒肆（三轨 jar）、妙音坊（三轨 jar）、钱庄（柜台累计）、医馆（病人队列）、药铺（病人池+计算队列）、庄园（产出仓）。

### 设计

新增 `systems/common/accrual.gd`：

```gdscript
class_name Accrual
extends RefCounted

var rates: Dictionary = {}      # key -> 每秒产量（float）
var stored: Dictionary = {}     # key -> 已累计量（float）
var cap_seconds: int = 0        # 0 = 无上限
var last_ts: int = 0            # unix 秒；0 = 未初始化

func _init(p_rates: Dictionary = {}, p_cap_seconds: int = 0) -> void
func set_rate(key: String, per_second: float, now: int) -> void   # 先 settle 再改
func settle(now: int) -> void
func peek(key: String) -> int
func claim(key: String) -> int
func to_dict() -> Dictionary
func from_dict(d: Dictionary) -> void
```

规则（必须逐条满足）：

- **不调用 `Time.get_unix_time_from_system()`**，`now` 一律由调用方传入。
- `last_ts == 0`：只初始化 `last_ts = now`，不发放。
- `settle` 幂等：同一 `now` 调两次结果不变；`now < last_ts` 按 0 处理。
- 上限：`stored[key] <= rate * cap_seconds`；`cap_seconds == 0` 表示不限。
- `claim` 返回 `floori(stored)`，只扣整数部分，保留小数余量。
- 序列化只含 `rates/stored/cap_seconds/last_ts` 四个键。

### 迁移范围（只做 2 个）

- `systems/inn_system.gd`
- `systems/tavern_system.gd`

**存档字段名与结构不变。** Accrual 只接管计算：`from_dict` 从原字段读，`to_dict` 写回原字段。不要新增存档键。

映射表（开工前先读这两个文件，把实际字段名补进报告）：

| 系统 | 原字段 | Accrual 键 |
|---|---|---|
| 客栈 | `pending` / `pending_ts` | `jiazi` / `chuyi` / `cook_count` |
| 酒肆 | `jar` / `jar_ts` | `yintiao` / `caiyi` / `serve_count` |

> 上表是占位，**以实际代码为准**；如果字段名对不上，停下来在报告里写清楚，不要猜。

### 验收

新增 `tests/snapshot_accrual.gd`：用假时间驱动，逐项对比重构前后。

用例（每个系统都要跑）：

| 用例 | 期望 |
|---|---|
| 初始化后立即 claim | 0 |
| +1h | 按 rate×3600 |
| +8h | 不超过 8h 上限（若配置 8h） |
| +24h | 不超过 24h 上限 |
| +48h | 同上限，不溢出 |
| 第 2h 改 rate | 前 2h 按旧 rate，之后按新 rate |
| 连续 claim 两次 | 第二次只拿新增部分 |

对比方式：重构前在 `d584beb` 上跑同一脚本，存 `tests/golden/accrual_baseline.json`；改后逐字节一致。

### 文件白名单

- `systems/common/accrual.gd`
- `systems/inn_system.gd`
- `systems/tavern_system.gd`
- `tests/snapshot_accrual.gd`
- `tests/golden/accrual_baseline.json`
- `docs/底座-阶段报告.md`

### 止损

只要有一个用例不一致，**回滚 B2，保留 B1**；不要靠改数值「对齐」。

---

## 6. B3：页面壳 + MedalTrack（约 1 周）

> ⏸ **暂缓开工。** 先做 [UI 路线 spike](UI路线-FairyGUI-spike.md)（2 天）。若 FairyGUI 通过，B3 的「页面壳」改为「FairyGUI 接入 + 迁 3 页」，`MedalTrack` 照做；若不通过，按本节执行。
> B1/B2 不受影响，可先做。

### 6.1 页面壳

`ui/base_view.gd` 已有 112 行，6 个玩法视图（winery/drugshop/tavern/clinic/inn/bank）已继承。**扩展它，不要新建基类。**

新增方法（只加不改）：

```gdscript
func make_topbar(page: Panel, title: String, on_back: Callable) -> HBoxContainer
func make_tabbar(page: Panel, tabs: Array, on_tab: Callable) -> HBoxContainer
func make_scroll_list(page: Panel) -> VBoxContainer
func make_empty(parent: Control, text: String) -> Label
```

约束：

- 不用锚点预设：`TOP_LEFT` + 显式 `position/size`。
- z-index 不变（页 35 / 页内弹窗 40 / 红点页内）。
- 节点名保持现有契约；不许改名。
- 顶栏高度、返回键尺寸、标题字号沿用现有页面的值（先量 3 个页面，取公约数）。

**迁移 3 页**：`bank_view`、`clinic_view`、`winery_view`。只换壳，不改内容/交互/文案。

### 6.2 MedalTrack

新增 `systems/common/medal_track.gd`：

```gdscript
class_name MedalTrack
extends RefCounted

var level: int = 1
var levels: Array = []   # [{name, need, shop_pct, refine_cap, ...}]

func _init(p_levels: Array, p_level: int = 1) -> void
func can_upgrade(points: int) -> Dictionary   # {ok, lv, need, have}
func upgrade(points: int) -> Dictionary       # {ok, lv}
func current() -> Dictionary
func next() -> Dictionary
func get_shop_pct() -> float
func get_refine_cap() -> int
```

**只迁 2 套**：`drugshop_system`、`fishing_system`（两者配置形状一致）。其余 4 套保持原样，下一阶段再说。

系统侧必须保留原公开方法，UI 零改动：

- `get_medal_lv()` / `get_medal_name()` / `get_medal_shop_pct()` / `get_refine_cap()` / `can_upgrade_medal()` / `upgrade_medal()`

存档仍用原字段 `medal_lv`，不迁移。

### 验收

- 3 个页面的节点树快照（name/type/size）前后一致：写 `tests/snapshot_pages.gd` 输出 JSON，基线对比。
- 勋章 lv1/5/10/15 的 `shop_pct` / `refine_cap` 与旧实现逐项相等。
- 用户真机截图对比 3 页（我验收时看截图）。
- headless 0 error。

### 文件白名单

- `ui/base_view.gd`
- `ui/pages/bank_view.gd` / `clinic_view.gd` / `winery_view.gd`
- `systems/common/medal_track.gd`
- `systems/drugshop_system.gd` / `fishing_system.gd`
- `tests/snapshot_pages.gd` / `tests/golden/pages_baseline.json`
- `docs/底座-阶段报告.md`

---

## 7. B4：主线解锁（只设计，不实现）

输出一份 `docs/主线解锁-设计.md`，包含：

- `data/quests.json` schema：`id / title / desc / cond{type,key,value} / rewards / next`。
- 条件类型：`stat`（`goal_stats`）、`stage_main`、`shop_level`、`have_hero`、`have_item`、`vip`。
- feature gate：`data/unlocks.json`，`feature_id -> quest_id`；`QuestSystem.is_feature_unlocked(id)`。
- UI 契约：府邸一个「当前目标」条 + 一个目标列表弹窗；不新增页面。
- 与 `goal_system` 的关系：`goal_system` 保留挚友目标，`QuestSystem` 管主线，不合并。

实现放 M1，不在本阶段写代码。

---

## 8. 我的验收清单（每阶段逐条过）

1. `git diff --stat` 只含白名单文件。
2. headless：退出码 0，无 `SCRIPT ERROR`。
3. golden 快照：`git diff --exit-code` 无输出。
4. 存档兼容：用重构前的档读入 → 保存 → 键集合不变。
5. 代码审查：
   - `shop_system.gd` 无 14 项链；
   - `Accrual` 无 `Time.` 调用；
   - 无新增 `push_warning` / `push_error`；
   - Tab 缩进；无关键字参数；`:=` 只用于可推断类型。
6. 性能：`get_total_auto_income()` < 20ms。
7. 回滚演练：`git revert` 后 headless 仍 0。
8. 阶段报告：改了什么/没改什么/怎么验，三句话能说清。

---

## 9. 风险与止损

| 风险 | 处理 |
|---|---|
| 浮点求和顺序变了，`int()` 差 1 | 注册顺序严格照表；快照差 1 也打回 |
| 客栈/酒肆存档字段对不上 | 停止，报告；不猜字段名 |
| 页面壳导致布局漂移 | 回滚 B3，保留 B1/B2 |
| 阶段超预估 1.5 倍 | 停下来报告，不硬做 |
| 想顺手重构别的系统 | 写进报告，不开工 |

---

*本文件是交接契约，不是建议。按阶段做，每阶段验收通过再进下一阶段。*
