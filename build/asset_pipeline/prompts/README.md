# 批量提示词目录

本目录由 `tools/asset_pipeline.py prompts` 生成。

任务文件：
- `task_XXXX_*.txt`：直接复制给豆包/绘图模型的提示词。
- `task_XXXX_*.json`：单元格到素材路径的映射，`slice` 命令会读取它。

工作流：
1. 先补全 `build/asset_pipeline/character_bible.csv`。
2. 运行 `python tools/asset_pipeline.py prompts`。
3. 按提示词生成图片，保存到 `build/asset_pipeline/inbox/atlases/`。
4. 运行 `python tools/asset_pipeline.py slice` 自动切图、抠底、命名并写入 assets。
5. 运行 `python tools/asset_pipeline.py qc` 批量验收。
