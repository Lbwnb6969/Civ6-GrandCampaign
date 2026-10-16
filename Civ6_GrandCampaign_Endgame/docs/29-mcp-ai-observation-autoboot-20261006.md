# Round 110：MCP AI 观测、菜单边界与自动加载保护（2026-10-06）

本轮继续开发 C:\Users\Administrator\Desktop\mIDDLEFILE\civ6-mcp-main，提交 374f198、c716dc2、483968e：

- 新增只读 GET /api/test/ai-observation，从现有 FireTuner diary 查询城市、生产、单位、收益和战略资源，并返回 elapsed_ms。
- POST /api/test/advance 为每一步和整次请求返回耗时，便于将来比较 AI 回合性能。
- /api/test/ai-mod-status 的 Lua 探针增加 API/表存在性保护、玩家读取保护、可选 Modding.GetActiveMods() 和 context_ready/错误计数；缺少 GameCore 时 fail-closed。
- 自动加载在启动前把 0_MCP_*.Civ6Save 移到 Saves\Single\_abandoned_mcp，不再删除；显式加载错误会快速返回并保持 HTTP API 可用。
- FireTuner 断开时，EOFError/OSError 统一返回 HTTP 503 Game not connected，避免菜单态堆栈错误。

MCP 回归为 116 passed；python -m compileall -q src tests 和 git diff --check 通过。当前 Civ6 停在主菜单，/api/test/ai-mod-status 与 /api/test/ai-observation 均正确返回 HTTP 503（无 GameCore/InGame），这只是连接边界证据，不能判定模组是否载入。后续应在有 GameCore 的 Endgame 存档中调用 AI 观测，记录 modifier/config、城市队列、单位、收益、战略资源、外交/战争和单回合耗时，并与同存档 A/B 对照。
