# 给 Kimi 的角色设定补全任务

请读取 `character_bible.csv`，补全两列：

- `canon_description`：80~150 字，说明该角色的身份、时代/职业、气质、标志性外貌。
- `appearance_keywords`：10~20 个中文关键词，描述 AI 绘画需要锁定的外观特征。

要求：
1. 不要修改 csv 的列名、行顺序、id、name、reference_image。
2. 历史/小说人物遵循大众认知；原创角色按名字和类别合理创作。
3. 输出仍是 UTF-8 CSV，直接覆盖 `character_bible.csv`。

补全后放回 `build/asset_pipeline/character_bible.csv`，再运行：

```bash
python tools/asset_pipeline.py prompts
```
