# Civ6 GrandCampaign Stability

## 当前目标

为大地图提供稳定诊断、万神殿后备池、自然奇观安全模式和卫星安全/分块揭图，确保未知原生数据不会冒充成功。

## 要求

- 保留原版行为及默认模式，安全/分块模式独立可选，不修改无关效果。
- 所有数据/源码显式UTF-8；重要版本保留Git和归档恢复点。
- 原生渲染、回合效果、存读档和大地图性能须实机验收。

## 关键决策

- 本轮用户已授权独立MCP/FireTuner单人实机检验，覆盖历史只离线限制；禁止Computer Use屏幕操作。
- GameInfo数据集合可以是可调用表，不用type==function判断其可迭代性。
- 万神殿使用状态不可读时报告UNKNOWN/pantheons_complete=false，不把失败当成0或未使用。
- 两项使用查询均明确false才视为可用；任一true即已占用；普通池未知且无确认可用项时不显示后备池。
- reserve belief复用原版atlas的12个显式图标定义；不依赖UI在缺图标后补救。

## 当前进度

- 2026-10-08 10:48 五仓库完整阶段恢复点native/checkpoint-20261008-1041已提交并核验bundle/zip。Endgame cbc479406dbdd90730b3cda2529fc81f20eefb9f，Research 6f5d127be02a4987b4f9c00a0711ab17ceeb26da。资源生命周期模块通过不代表AI正常行动：629再次复国后631–633跨真实回合AI队列仍空，637/638 CheckActiveProduction未补队列；正在对照复国保存重载后的原生AI行动。不得将Alive/城市计数包装成AI完整闭环。

- 2026-10-08 10:40 资源生命周期V3模块原生闭环通过：使用COLLECTION_PLAYER_CITIES计数，611–613真实归档/归还/标记解除，615继续真实回合，616再次失最后城市正常败亡；619/621复国保存重载一致；622–629重复归档、实际保存/下一回合/重载/再次复国通过。630核验当前源码SHA与真实规则类型。V2普通败亡失败602/603已完整归档，构造器阻止旧规则混用。标准玩法新规则全程、AI队列、其他胜利/Stability/大地图/最终门禁仍待完成，详见证据49。

- 2026-10-08 10:27 资源生命周期复国仍未通过：569归还后移除资源导致570真实Alive=false（城市1）；574–577回滚归档夹具、归还保留资源并推进真实回合后，默认败亡要求仍未重开。V2追加原生城市数量条件并在解除标记前验证，6项定向及Steam SQL通过；585/587/588新局归档、保存和真实回合通过，但零城数量条件仍NotMet，重载/复国与普通败亡对照正在核验。详见Research/docs/49-resource-lifecycle-native-20261008.md，不能将模拟或归城局部成功算完整复国。

- 2026-10-08 09:59 三模组组合的准备期人类真实征服胜利、候选标记释放与终局保存/严格原生重载通过（538/539/543/547/548），本项目源码未变，专项和大地图仍未验收。

- 2026-10-08 09:32 三模组V2六文明小局实际保存重载、连续推进至T9并触发觉醒候选者原生征服胜利；本项目源码未变，此组合结果不替代万神殿/奇观/卫星/气候专项。气候level0/points-1/seaLevelRows=false属于数据诊断限制，不能记全功能通过。专项与目标大地图仍待验收。

- 2026-10-08 07:55 三模组V7组合的人类标准复国保存重载、原队列/12点产能保持及T65→T66真实推进通过；本模组源码未改，不能将组合基础回合结果代替万神殿/奇观/卫星/气候专项。专项与大地图仍待验收；最终原auto/profile恢复待完成。

- 2026-10-08 V7三模组正常Native模式已真实普通建城、T1→T2（292，6839.89ms）及保存回调通过。此前观测对照原生访问违规证据在284；生产恢复桥缩小扫描后恢复启动，Stability本身未改。专项万神殿/奇观/卫星/气候仍待实测，不用基础回合成功替代。最新五仓库已核验恢复点native/checkpoint-20261008-0153；最终原auto/片头/mod profile恢复仍待完成。

- 2026-10-08 01:06：原自动存档3/50的三模组对照，普通建城与T1→T2、复国夹具重载后的T2→T3通过。正常Native模式仍待修复；本轮万神殿/奇观/卫星/气候专项尚未完成。自动存档已恢复原值，原auto仍受保护并需交付前移回。

- 2026-10-08：核心测试出现正常模式卡死、V5复国后回合0xC0000094崩溃，仍在独立对照定位，不归因于Stability单一模块。Stability本轮验收尚未通过。正常auto暂存受保护目录，恢复位置及自动存档/模组选项要求见Research当前PROJECT；最终交付须恢复。

- 先前用户日志已有正常/AI reserve万神殿创立及自然奇观安全跳过事件，两个ReplaceUIScript已加载。
- 保留可调用GameInfo.Beliefs表兼容；本次修复查询nil被当作可选、一项false掩盖另一项失败，以及普通池未知时错误开放后备池的问题。
- 新增3项万神殿UI/诊断回归先失败后通过；确认前状态变为未知时不会发送选择操作。
- reserve图标、卫星状态队列和气候诊断已有静态合同及行为回归；不宣称原生复测通过。

## 下一步

- 按Research文档46进行本轮独立小局验收，再验证目标大地图和后期对象预算。
- 本轮通过MCP核对真实计数、选择后回合继续和自然奇观后的地图操作；图标实际渲染/实体输入受禁止屏幕操作限制，不能以API读取冒充视觉验收。
- 有合适后期存档后核对卫星跨读档单次处理、分块模式覆盖及大地图回合耗时。
- 与Endgame组合的具体实机顺序见[可玩验收](../Civ6_GrandCampaign_Research/docs/42-playable-acceptance-20261007.md)。

## 未解决问题

- reserve图标和万神殿诊断修复尚未实机复测；历史全0记录不能当成信仰池为空。
- 卫星/后期大地图、原生存读档和各可选模式仍缺完整通过证据。

实现详情见[离线交付](../Civ6_GrandCampaign_Research/docs/43-offline-development-20261007.md)。

## 验证与恢复点

- 本轮修改前标签 `backup/native-20261007-191536`，完整bundle/源码zip及正常存档保护位于 `C:/Users/Administrator/Documents/Civ6_GrandCampaign_Backups/20261007-191536-native-pre`。
- 历史系统续查未修改本模组源码；组合SQL、manifest和本地化通过（132键/264行），该轮仅离线。本轮已启动独立三模组小局，Stability各功能验收尚待完成；当前记录见[文档46](../Civ6_GrandCampaign_Research/docs/46-native-completion-20261007.md)。
- 四仓库最新完整备份：`20261007-141306-systems-pre/post`，标签`backup/systems-20261007-141306`与`systems/20261007-141306`，位于`C:/Users/Administrator/Documents/Civ6_GrandCampaign_Backups`。

- 2026-10-07完整静态门禁一次通过：17套件521/521、44文件编译；卫星43/43、万神殿UI17/17、气候/万神殿诊断12/12、自然奇观UI3/3。
- Steam SQL/XML、131键/262行本地化、UI/布局/manifest、PowerShell/UTF-8、TestFlow、证据工具11/11通过；相关MCP离线pytest166项及compileall通过。
- 上述完整静态结果来自历史离线轮次；本轮原生验收未完成，不复用历史日志宣称通过。
- 四仓库变更前标签：`backup/review-20261007-121832`；完整bundle及日志位于 `C:/Users/Administrator/Documents/Civ6_GrandCampaign_Backups/20261007-121832-review-pre`，变更后提交和增量bundle位于同级review-post目录。
- 详细修复和剩余风险见 [检查记录44](../Civ6_GrandCampaign_Research/docs/44-comprehensive-review-20261007.md)。

## 历史记录

完整旧PROJECT已移动至[历史归档](docs/_abandoned/PROJECT-history-20261007-offline-development.md)，以本文件当前结论为准。
