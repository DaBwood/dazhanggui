# 大掌柜素材流水线

核心原则：默认皮肤是角色本体，服装是道具。所有服装必须基于默认皮肤生成。

```powershell
# 0) 扫描与角色设定
python tools/asset_pipeline.py scan
python tools/asset_pipeline.py prompts --phase base
# 用 Kimi 补全 build/asset_pipeline/character_bible.csv，然后重新执行上面这条 prompts

# 1) 默认皮肤：每个门客/挚友一张，共 224 张缺失任务
python tools/asset_pipeline.py generate --kind portrait_single
python tools/asset_pipeline.py slice

# 2) 服装：默认皮肤已存在后，再生成服装图集；提示词会自动带默认皮肤参考图
python tools/asset_pipeline.py prompts --phase costume
python tools/asset_pipeline.py generate --kind costume_sheet
python tools/asset_pipeline.py slice
python tools/asset_pipeline.py derive

# 3) 图标：技能/道具/珍兽/渔获/促织，九宫格批量生成
python tools/asset_pipeline.py prompts --phase icons
python tools/asset_pipeline.py generate --kind icon_sheet
python tools/asset_pipeline.py slice

# 4) 验收
python tools/asset_pipeline.py verify
python tools/asset_pipeline.py qc
```

如果不用 Volcengine API，也可以只生成提示词，然后用豆包网页端逐张生成；
把图片按提示词里的文件名放进 build/asset_pipeline/inbox/atlases/ 即可。

## 当前项目扫描结果

- 素材契约：2062 条
- 缺失：1931 条
- 默认皮肤：224 张（门客 108 + 挚友 116）
- 服装全身：449 张
- 服装小图标：449 张（derive 本地派生，不调 AI）
- 技能/促织/道具/珍兽/渔获图标：700 张（图标图集 80 张）
- 门客卡图：109 张（derive 本地派生）

总计需要交付给 AI 的任务：
- 默认皮肤单图 224 张
- 服装图集 159 张（覆盖 449 套服装）
- 图标图集 80 张（覆盖 700 个图标）
- 合计 463 个生成任务，另有 558 张图标/卡图由脚本派生。

## 关键目录

- build/asset_pipeline/manifest.csv：素材总清单
- build/asset_pipeline/character_bible.csv：角色外貌设定表
- build/asset_pipeline/prompts/task_*.txt：完整提示词
- build/asset_pipeline/prompts/task_*.json：格子到素材路径的映射
- build/asset_pipeline/inbox/atlases/：生成图入口
- build/asset_pipeline/qc/index.html：批量验收页

## Volcengine API

npx -y @volcengine/skills-setup@latest 已经安装 ve 和 arkcli。
使用前需要登录：

```powershell
ve arkcli auth login
# 或
ve arkcli auth apikey
```

然后可以直接：

```powershell
python tools/asset_pipeline.py generate --model doubao-seedream-5-0-pro-260628 --size 2048x2048
```
