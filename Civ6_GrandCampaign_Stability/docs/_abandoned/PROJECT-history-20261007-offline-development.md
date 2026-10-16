# 项目状态：Civ6 GrandCampaign Stability

## 当前目标

为超大地图提供稳定性诊断、卫星分批开图、气候诊断、万神殿后备信条和自然奇观安全模式，并在原生 API 不确定时暂停或报告 UNKNOWN。

## 要求

- 只在配置明确开启时执行安全模式或实验逻辑。
- 重要旧文件保留在 `Civ6_GrandCampaign_Backups` 和 Git 标签中。
- 所有脚本、XML、SQL 和文档使用显式 UTF-8。

## 关键决策

- 卫星开图按回合预算、属性提交和可恢复队列运行；失败时暂停，不把未知地图状态当作完成。
- 万神殿替换沿用原版确认/关闭流程，只在普通池耗尽时显示后备信条。
- 自然奇观安全模式只观察发现事件并跳过可能阻塞回合的电影、镜头和临时可见性。

## 当前进度



- 2026-10-07 已修复万神殿诊断的可调用 GameInfo.Beliefs 表兼容；使用状态不可读时报告UNKNOWN/pantheons_complete=false，离线原生表形态和失败分支通过。
- reserve 图标与自然奇观/正常万神殿事件已有此前日志；图标修复、卫星/后期大地图及存读档仍未实机复测。
- 本轮静态构建优先，不启动游戏；实现见 [离线交付](../Civ6_GrandCampaign_Research/docs/43-offline-development-20261007.md)。

### 既有记录（截至本轮前；当前结论以上文为准）

- 当前静态轮次为 R134：两个 `ReplaceUIScript` UI replacement 继续对照本机 Steam 原版 XML 核对 Lua 控件和实例引用；统一入口同时验证 Endgame 总览数据链、LaunchBar 原生资产、Research、Stability、TestFlow 和 MCP，本项目仍不启动游戏。
- 文本覆盖 32 个键，中文/英文均已有入库验证。
- 卫星队列、排序、可见性和快照诊断统一安全读取玩家 ID；身份不可读时保留队列，诊断标记不完整。
- 开图接口明确返回 false 时暂停并保留失败地块；nil 返回仍兼容原生无回执接口。
- 本轮受影响源码回归：卫星 43/43、气候 9/9、Pantheon UI 15/15、自然奇观 UI 3/3；坏 Belief 行、可见性容器索引、原生 userdata 成员查找、万神殿操作失败、音效 API 异常、图标 atlas 异常、事件暂时不可用后的延迟恢复和自然奇观事件延迟恢复均在旧源码上先失败，修复后通过。42 个 Lua 文件编译通过。
- Endgame 与 Stability 的玩家、地图、集合、可见性和事件 API 先做受保护的可调用性检查，再进入既有失败隔离；GameInfo 数据库代理保持索引/迭代访问。
- 自然奇观安全弹窗对事件对象的成员查找和卸载也做受保护检查；现在按 vanilla 的 `SetInitHandler`/`SetShutdown` 生命周期幂等注册，重载时先移除旧监听再绑定，异常时记录不可用并让 UI context 正常结束。
- 万神殿替换 UI 在宗教对象读取失败或重载后不可用时保持空态，不让异常 API 破坏整个替换 context。
- 万神殿替换 UI 会跳过缺少 BeliefType、Index、Hash 或文本字段的损坏行；自然奇观替换按 vanilla context 生命周期幂等注册，卸载时清理监听。
- 万神殿替换 UI 将三条 LuaEvents 逐条记录绑定状态；某条事件暂时不可读或 Add 失败时不会误标记为完成，下一次初始化会只重试缺失事件，控件回调仍只注册一次。
- 卫星分块读取 `PlayersVisibility[playerID]` 失败时会保留队列并暂停，不把索引异常带出回合回调。

## 下一步


- 按[可玩验收方案](../Civ6_GrandCampaign_Research/docs/42-playable-acceptance-20261007.md)核对 reserve 图标错误是否消失、reserve 分支选择后可继续回合、自然奇观安全模式后地图可操作。
- 万神殿诊断原因已静态修复，待核对下一次原生日志；有合适后期存档后验收卫星队列跨读档幂等及大地图回合性能。

### 既有记录（截至本轮前；当前结论以上文为准）

- 在与 Endgame 同时启用的真实新进程中确认配置项文本、万神殿后备池、自然奇观安全模式和大地图分批开图。
- 收集原生日志后再决定是否需要针对具体 API 或模组冲突修复。
- 下一会话先读取 Research 的 `docs/23-handoff-20261004.md`，沿用当前提交和备份，不重复覆盖既有 Git 历史。

## 未解决问题


- 尚无卫星/大地图完整后期及读档通过证据；reserve 图标修复尚未实机复测。
- 日志计数的原生可调用表兼容已修复，仍需原生日志复测；历史0不能据此判定信仰池为空。

### 既有记录（截至本轮前；当前结论以上文为准）

- 尚无本轮最新进程对极大地图真实性能和所有可选安全模式的完整证据。

## Round 113：静态验证与运行时边界（2026-10-07）

本轮 Stability 静态合同继续 PASS，Research workspace/PowerShell 与 Stability SQL 校验无失败。MCP 的 active-mod 只读探针确认：目标存档进入游戏并不等于 Stability/Endgame 已参与该局，后续大地图/卫星安全模式验证必须先确认目标 ID 出现在 active 集合。

## Round 114：静态构建优先（2026-10-07）

用户确认 Stability 已启用；本轮不再启动游戏或进行屏幕操作。稳定性模组先以 SQL/XML、Lua 编译、workspace 合同和异常边界回归作为交付标准；active-mod 探针不作为启用状态的权威判断。

## Round 115：组合静态验证与 UI 边界（2026-10-07）

Research 的 `validate-all-static.ps1` 已将 Stability SQL/Lua/workspace 检查与 Endgame UI 合同、TestFlow 静态检查串成单一入口。Stability 没有额外可见 UI action；其 Pantheon/NaturalWonder UI replacement 继续由 modinfo criteria 门控，Endgame 的左上角入口和只读面板边界记录在 Research `docs/34-ui-surface-audit-20261007.md`。不新增游戏运行时结论。

## Round 120：项目文档结构契约（2026-10-07）

Research 聚合入口现在检查 Stability PROJECT.md 的恢复字段，并统一记录静态构建优先、不启动游戏的验证边界；本轮不新增 Stability 运行时结论。

## Round 121：PROJECT schema 校验器（2026-10-07）

Research 新增 `tools/validate_project.py`、`schema/project.schema.json` 和聚合兼容入口，PROJECT.md 的目标/要求/决策/进度/下一步/未解决问题字段现在按 schema 结构检查；本轮不改变任何游戏运行时结论。

## Round 123：静态优先边界强制（2026-10-07）

PROJECT schema 校验器现在要求每个项目文档显式记录 static-first 边界；聚合验证继续覆盖 UI、事务、SQL/XML、Lua、TestFlow 和 MCP 文档。该轮不启动游戏、不新增原生运行时结论。

## Round 124：Endgame UI 几何布局合同（2026-10-07）

Research 新增 `tests/validate-ui-layout.py`，静态检查左上角按钮/图标、总览面板、滚动区和档案行的固定尺寸、锚点与重复 ID；本轮不启动游戏，不把几何合同当作原生渲染证据。

## Round 125：事务状态 footer 防遮挡（2026-10-07）

总览面板现在读取 `OperationStatus` 和只读提示的实际控件高度，动态预留底部空间，长本地化状态不会侵入档案滚动区；Research 总览回归为 `46/46`。本轮不启动游戏。

## Round 126：MCP 纳入统一静态门槛（2026-10-07）

Research 聚合静态入口现在同时验证 MCP 的离线 pytest、Python 编译和差异检查；Stability 继续只依赖静态合同，不启动游戏。Round129 post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261007-round129-static-gate-docs-post`。

## Round 127：static-first / MCP 构建手册（2026-10-07）

Research 新增静态构建手册，记录 Stability 的 SQL/Lua/workspace 合同如何与 Endgame UI、TestFlow 和 MCP 门槛一起运行；本项目不新增游戏运行时结论。

## Round 128：MCP 存档清理改为可恢复归档（2026-10-07）

MCP 清理路径现只移动旧存档到 `_abandoned_mcp`；Stability 继续只依赖静态合同，不新增游戏运行时结论。

## Round 129：MCP telemetry 清理改为可恢复归档（2026-10-07）

MCP telemetry 清理路径现只移动观测证据到批次归档目录；Stability 继续只依赖静态合同，不新增游戏运行时结论。

## Round 130：Stability UI replacement 合同（2026-10-07）

Research 新增 `validate-stability-ui-contract.py`，核对 PantheonChooser 与 NaturalWonderPopup 的 `ReplaceUIScript` action、原生 LuaContext、LoadOrder、criteria、manifest 路径、生命周期入口和屏幕注入 API 禁止项；两个 replacement UI 仍需原生进程确认实际替换顺序，本轮不启动游戏。

## Round 131：Stability replacement 对照原版 XML（2026-10-07）

静态合同现在读取本机 Steam 的 PantheonChooser/NaturalWonderPopup XML，核对 replacement Lua 的 `Controls.*`、`InstanceManager` 实例名和实例控件 ID；官方 XML 仅作为只读参考，不修改其重复属性或内容。原生替换顺序和模组冲突仍待实际进程验证。

## Round 132：MCP UI 证据汇总接入（2026-10-07）

统一 MCP UI probe 现在为每个候选 state 保留名称、索引和证据等级；这为 PantheonChooser/NaturalWonderPopup replacement 与 Endgame UI 的后续一次性运行时对照提供定位信息，但本轮仍只做静态验证，不启动游戏。

## Round 133：组合 UI 数据合同静态门槛（2026-10-07）

Research 统一静态入口新增 Endgame 总览模型/面板/文本数据合同校验；Stability 的两个 `ReplaceUIScript` 仍先通过自身原版 XML 对照和生命周期合同，再与 Endgame/TestFlow/MCP 一起构建。该轮只补强组合静态可恢复性，不启动游戏，也不把 UI probe 或静态字段通过解释为 replacement 已在原生进程生效。


## Round 135：MCP replacement surface 定位摘要（2026-10-07）

MCP 只读 UI probe 的 surface 摘要现在能定位 PantheonChooser 与 NaturalWonderPopup replacement 的候选 state，并保留 `INCOMPLETE`/可见控件证据等级；本轮不启动游戏，不把定位结果当作 replacement 已生效。

## Round 136：MCP replacement surface 状态摘要（2026-10-07）

MCP 只读探针现在为 PantheonChooser/NaturalWonderPopup replacement 输出候选数和最高证据等级；空候选只表示本次没有可定位 context，不推断 replacement 未启用。本轮不启动游戏。

## Round 137：HTTP replacement 验收入口同步（2026-10-07）

PantheonChooser/NaturalWonderPopup 的后续运行时定位统一使用 MCP HTTP UI 验收脚本；静态 replacement 合同和 fail-closed 边界保持不变。本轮不启动游戏。

## Round 138：MCP UI surface 跨仓库合同同步（2026-10-07）

Research 新增跨仓库静态检查，确认 `PantheonChooser` 与 `NaturalWonderPopup` 的原生 context、Lua 替换路径和 MCP `pantheon_replacement`/`natural_wonder_replacement` surface 保持一致。本轮只做静态构建，不把名称匹配解释为 replacement 已在原生进程生效。

## Round 139：运行日志图标缺口修复（2026-10-07）

实机 `UserInterface.log` 确认 reserve Pantheon replacement 已加载，但原生 IconManager 报 `ICON_BELIEF_GMS_RESERVE_GROWTH_03` 缺失。新增 `Data/GMS_Icons.xml` 和 `GMS_Icons` InGame action，为 12 个 reserve belief 名称映射 vanilla Pantheon 图集；Lua 层保留同一映射作为运行时兜底。另记录 LaunchBar 卸载阶段的 ButtonStack 竞态，归 Endgame 修复。本轮不重复启动游戏。

## 本轮可玩验收同步（2026-10-07）

总览行为48/48、44 Lua compile-only、UI/本地化/项目结构及Stability图标合同通过；命令和恢复点见 Research PROJECT Round149。仅表示静态验证通过，尚未实机复测；完整可玩缺口按文档42执行。
