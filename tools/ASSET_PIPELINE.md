# 大掌柜素材流水线

把"截图 -> 豆包重画 -> 手工抠底 -> 手工命名 -> Kimi 适配"改成可批量执行：

```powershell
python tools/asset_pipeline.py scan
python tools/asset_pipeline.py prompts
# 把生成图按提示词文件名放进 build/asset_pipeline/inbox/atlases/
python tools/asset_pipeline.py slice
python tools/asset_pipeline.py derive
python tools/asset_pipeline.py verify
python tools/asset_pipeline.py qc
```

当前扫描：2063 条素材契约；实际交给绘图模型的只有 312 张图集，覆盖 1375 个独立素材。
457 个服装小图标、109 个门客卡图由脚本从立绘本地派生，不再让 AI 重画。

产物目录：
- `build/asset_pipeline/manifest.csv`：素材总清单
- `build/asset_pipeline/character_bible.csv`：角色外貌设定表
- `build/asset_pipeline/prompts/task_*.txt`：豆包提示词
- `build/asset_pipeline/prompts/task_*.json`：格子到素材路径的映射
- `build/asset_pipeline/inbox/atlases/`：生成图集入口
- `build/asset_pipeline/qc/index.html`：批量验收页

详细说明见 `build/asset_pipeline/prompts/README.md`。
