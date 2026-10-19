# AGENTS.md — 《大掌柜》项目工作指引

> DSH 每次开工自动加载本文件，只放「动手前必须知道」的最小集。
> 详细文档在仓库内：[开发规范](docs/开发规范.md)（规矩）、[开发档案](docs/开发档案.md)（状态/待办）、[踩坑](docs/踩坑.md)（教训）。
> 最后核验：2026-10-19，对着仓库实测，不是抄旧档案。

## 1. 项目与环境

- Godot 4.7.1 竖屏放置经营手游，设计分辨率 600×1067，纯 GDScript + 外置 JSON 配置。
- 工作目录即仓库根，`main` 分支，与 origin 同步。旧文档里的行号、MD5、批次状态一律不可信，**以现码 + `git log` 为准**。
- 引擎：`C:\Users\林\Documents\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe`（4.7.1.stable.official，已实测可跑）

### 开工自检（30 秒）

```powershell
# 必须重定向 APPDATA：否则 user:// 日志写不进沙盒，引擎直接 signal 11 崩溃
$env:APPDATA = Join-Path $env:TEMP 'dzg_godot_user'
& 'C:\Users\林\Documents\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --quit
```

- 退出码 0 且无 `SCRIPT ERROR` 才算基线干净（退出时的 ObjectDB/resource leak、证书库读取失败属已知噪声，可忽略）。
- 单文件语法检查：`--check-only --script res://systems/xxx_system.gd`。
- 只用这两条做交付前验证；「静态审计全绿」不能替代真解析。

### 协作边界

- 不主动 commit / push。改完给 `git diff` 摘要，用户真机测过自己推。
- 交付 = 直接改工作区文件。不打包 zip、不在回复里贴整文件（旧工作流是为无文件权限的沙盒设计的，此处不适用）。

## 2. 文件地图

| 位置 | 职责 | 关键锚点（会漂移，按符号 grep） |
|---|---|---|
| `game_controller.gd`（1655 行） | 场景壳、页面/视图分发、全局刷新 | `VIEW_LIST`(92) `PAGE_CLOSE_LIST`(122) `_enter_game`(182) `switch_page`(294) `update_all_ui`(455) `show_view`(1090) `_apply_portrait_layout`(1594) |
| `game_data.gd`（1982 行） | 中枢：状态、系统实例、配置、转发器 | `SYSTEM_LIST`(667) `CONFIG_SPECIAL_LOADERS`(713) `_check_orphan_configs`(1001) |
| `hero_data.gd` | 门客资质/「赚钱」唯一计算入口（纯静态，不可 new） | `_bonus_registry`(52) |
| `systems/*.gd`（40 个） | 纯逻辑 RefCounted，持 `var g` = GameData | |
| `ui/pages/*.gd`（40 个） | 纯 UI RefCounted，持 `var c` = controller、`var data` = GameData | |
| `ui/ui_helpers.gd` | 弹窗工厂、结果/规则弹窗、公共控件（**真正的实现处**） | `_create_base_popup`(54) `_show_rule_popup`(684) `_show_success_popup`(704) |
| `data/*.json`（43 张） | 外置配置，概率用权重制 | |
| `云存档/server.js` | 国内 VPS 实际运行的服务端（Cloudflare 版 worker.js 已删除，只维护这一版） | |

- systems 用 `g.xxx`；pages 只有 `c`/`data`，**没有 g**；RefCounted 模块没有任何 Node 方法，节点操作一律走 `c`。
- `data.heroes` 只含已拥有门客；全量配置查 `data._hero_configs`。

## 3. 硬红线

### GDScript

- **Tab 缩进**，不是空格。
- GDScript 不支持关键字参数（`f(a = 1)` 式调用非法）。
- Godot 4 没有 `is_node_being_deleted`。
- JSON 数字全是 float：当字典 key、取模、循环次数前先 `int()`；Dictionary 的 int 键落盘会变 string（槽位键统一按字符串写，读取双查兜底）。
- `:=` 只用于可推断类型；`g.xxx`、字典下标、`min/max`、`.keys()`、`get_node` 一律显式标注。
- `and/or` 返回 bool；多行 lambda 不能直接链 `.bind()`；循环变量按引用捕获，跨 lambda 改状态用 Dictionary/Array。
- tween/timer 回调首行 `is_instance_valid` 守卫；闭包只捕路径/int，不捕节点。
- 整数取大小用 `mini/maxi`，整除用 `floori()`；变量名避开 `seed/sign/wrap/floor/exp`。

### UI

- 新建 Button 当帧 `size=(0,0)`，必须显式赋 size 或 `custom_minimum_size`；TextureRect 先 `expand=true` 再设尺寸。
- 不用锚点预设：`TOP_LEFT` + 显式 position/size。
- 布局真相源分两种：**老页面**（代码建 UI）由 `_apply_portrait_layout` 统一赋尺寸；**场景化页面**布局只在 tscn，脚本禁二次钉布局。两种都不许混用。
- 弹窗工厂**只创建不挂树**，调用方必须 `c.add_child(popup)`；弹窗一律挂 `c` 根节点。
- **弹窗工厂有两个入口，签名不同（实测确认）**：
  - `c._create_base_popup(title, size, pos, with_close)` —— 4 参，`decorated` 写死 true（皮肤版）。
  - `ui_helpers._create_base_popup(title, size, pos, with_close, decorated)` —— 5 参；`decorated=false` 才是素面（规则说明弹窗用）。
  - 想让弹窗素面却走 `c.` 前缀，参数会被吃掉或直接报错。
- z-index（仓库实测分布）：25 遮罩 / 30 弹窗 / 35 全屏页 / 36–38 抬层 / 39 页内遮罩 / 40 页内弹窗 / 45 确认 / 50 飘字 / 60 拖影 / 88 SyncMask / 90 登录门 / 95 对账顶窗。
- **禁止同帧「删旧 + 重建同名弹窗」**：`queue_free()` 帧末才删，同帧重建会被自动改名，按名查找/关闭全部落空 → 原地重建内容。
- 反馈统一 `c._show_success_popup(文本, auto_hide, kind)`：`ok` 金 / `warn` 红。
- 品质色：普通 `#f2f2f2` / 优秀 `#3498db` / 卓越 `#9b59b6` / 传奇 `#e67e22` / 无双 `#e74c3c`。

### 数据与配置

- 新系统 = `SYSTEM_LIST` 一条（key/script/cfg_var/cfg）+ var 声明；实例化、存读档、启动校验全吃这张表，不要再手写第二份数组。
- 新 JSON 必须被 `SYSTEM_LIST` 的 cfg 或 `CONFIG_SPECIAL_LOADERS` 认领，否则启动 `push_warning`。
- 写完 JSON 必须全量解析校验（末键逗号坑已踩四次）；项目 JSON 是 Tab 缩进风格，**不要整体 dumps 重写**，要逐行增量插。
- 公式类配置必须代 Lv1 / 20 / 100 / 600 验算，别只验满级。
- 概率用权重制；percent 一律小数制，配置里的百分数在消费端 `/100`。

### 手法

- 引用任何函数名、字段名、配置键之前先 grep 确认存在——编造符号是历史最高发事故。
- 同文件多处修改串行做，改一处读一次；并行编辑会静默丢改。
- 手写 tscn：`[ext_resource]` 必须全部排在 `[sub_resource]` 之前，注释符是 `;` 不是 `#`。
- 多行替换/改缩进后，用栈式块解析器验结构（`elif/else` 必须紧接同层 if 块尾），肉眼只看缩进会漏位置错。

## 4. 场景化页面范式（当前主线）

- `SCENE.instantiate()` 后先 `free()` 旧壳再挂新壳（用 `free` 不用 `queue_free`，同帧重建会断契约）。
- 必需节点用 fail-loud：`get_node` 直取，缺件立即报错，不写静默兜底。
- 脚本只灌动态内容（列表/数值/信号接线），静态排版留在 tscn。
- 节点名是跨文件契约；改节点位置要全仓同步 `get_node` 路径。

## 5. 口径（代码注释与玩家 UI 都按这套）

- 门客个体战力叫「**赚钱**」；全局挂机货币获取速度叫「**赚速**」，不得混用。
- 品质四档：0=优秀 / 1=卓越 / 2=传奇 / 3=无双（`heroes.json` 显式写）。
- 未接入的玩法在玩家 UI 统一写「后续版本开放」，机制说明不进玩家界面。
- 效果描述写公式 + 叠加关系，不写「已生效」。
- 百分比加成链走 `hero_data._bonus_registry` 注册表（`game_data.gd` 侧 `register_bonus`），不要直接改 `get_percent_bonus`。

## 6. 当前进度（2026-10-19 核验，开工先跟用户确认是否最新）

- HEAD = `4eecbdc`「酒肆迁移改造」（2026-10-17 23:05）；之前是弹窗皮肤 v13 收官 + 图标日。
- **待确认**：酒肆迁移这批是否实测通过——旧档案只写到「已交付待实测」，没记收尾。
- 已销项（旧档案挂了但代码确认完成）：促织「红牙白/射弓红」命名、三玩法勋章 skill_cap 聚合接入。
- 未开工（已核 0 引用/0 文件）：商会三期 BOSS、山庄。
- 未核：11 个页面自造面板换肤的名单、资质技能图标 106 名。
- 主线策略：场景化「按需」推进（哪页闹心迁哪页），不再追全量手工 new 清零。

## 7. 从 Kimi 旧档案继承时的取舍

**不要照搬**（都是为无文件系统权限的沙盒服务的，这里不适用）：
GitHub 镜像/gh-proxy 拉 zip、ipython 下载解压、`/mnt/agents/output|upload` 交付、REF 标签、MD5 回读登记、≤4 单发 / >4 zip 规则、upload 属主 root 只读、ipython 内核重置、平台 backup 快照、Kimi 2.6 分工。

**保留**：引擎级/项目级事实已整理进 `docs/`，本文件只留最小集。
**历史批次细节**：需要时向用户要旧档案原文，但结论必须重新对仓库核验，不要凭印象补。
