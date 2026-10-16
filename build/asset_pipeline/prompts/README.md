# 批量提示词目录

本目录由 `tools/asset_pipeline.py prompts` 生成。

任务文件：
- `task_XXXX_*.txt`：直接复制给豆包/绘图模型的提示词。
- `task_XXXX_*.json`：单元格到素材路径的映射，`slice` 命令会读取它。

工作流（默认皮肤优先）：
1. 先补全 `build/asset_pipeline/character_bible.csv`。
2. 运行 `python tools/asset_pipeline.py prompts --phase base`，生成全部角色默认皮肤提示词。
3. 生成默认皮肤图，保存到 `inbox/atlases/`，运行 `python tools/asset_pipeline.py slice`。
4. 再运行 `python tools/asset_pipeline.py prompts --phase costume`，此时服装提示词会带默认皮肤参考图。
5. 生成服装图集，保存到 `inbox/atlases/`，运行 `slice` 和 `derive`。
6. 如需图标，运行 `prompts --phase icons`，生成后同样 `slice`。
7. 最后运行 `verify` 和 `qc`。
