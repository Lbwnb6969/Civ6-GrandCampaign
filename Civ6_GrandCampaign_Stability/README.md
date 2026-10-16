# Grand Map Stability

2026-10-12用户重新授权最终验收，历史收尾暂停已失效。当前结论以[PROJECT.md](PROJECT.md)及[数值表70](../Civ6_GrandCampaign_Research/docs/70-awakening-selection-and-force-policy-20261012.md)、[原生记录71](../Civ6_GrandCampaign_Research/docs/71-native-acceptance-recovery-20261012.md)、[大图压力72](../Civ6_GrandCampaign_Research/docs/72-ynamp-object-pressure-20261012.md)、[AI宗教胜利73](../Civ6_GrandCampaign_Research/docs/73-awakened-ai-religious-victory-native-20261012.md)为准；其余旧记录是历史证据。当前仅操作GC_独立单人测试，未载入或推进正常人工存档；不宣称全部验收通过。

当前自然气候T39终态保存严格重载／T40和目标YnAMP180×94／24人初期读档已通过（[记录61](../Civ6_GrandCampaign_Research/docs/61-control-return-climate-ynamp-20261009.md)）；下文“终态未保存／未启动”属于历史时点。目标大图卫星16920格终态及重载已通过，24文明120城/1389单位对象压力及重载已通过；实体Chooser、自然晚期／兼容仍待，当前源码统一静态门禁已通过，准确下一步见[PROJECT.md](PROJECT.md)。组合新增候选败亡修复与速度证据见[记录65](../Civ6_GrandCampaign_Research/docs/65-awakening-speed-and-candidate-invalidation-20261009.md)，本项目玩法源码未因该修复变化。

组合验收更新：觉醒经济优势与取消直接战斗力见[记录64](../Civ6_GrandCampaign_Research/docs/64-awakening-economic-bonuses-20261009.md)。本项目游戏源码未因这次玩法修正改变；各自原生范围及未完成项仍按下文记录。

2026-10-07检查已修复万神殿未知状态误判：两项使用查询均明确false才视为可选，普通池未知时不开放后备池，确认前失效则停止提交。静态门禁通过，实机效果待复核；见 [检查记录44](../Civ6_GrandCampaign_Research/docs/44-comprehensive-review-20261007.md)。

游戏内名称为“超大地图稳定性”。`Civ6_GrandCampaign_Research` 文件夹只保存文档和离线测试，没有 `.modinfo`，不需要在游戏里启用。2026-10-03 已修复翻译 XML 缺少语言字段导致的加载失败；8 个高级设置及说明、12 个后备万神殿全部提供简体中文与英文备用文本，可在游戏内停用再启用模组刷新文本，返回高级设置确认界面。详情见 [本地化修复记录](../Civ6_GrandCampaign_Research/docs/18-localization-audit-20261003.md)。

这是 Round 3 的稳定性模组。启用后写 `[GMS]` 日志，并可通过高级设置加载 12 个后备万神殿；PantheonChooser 会优先显示普通候选，普通候选为空时才显示后备候选。另有默认关闭的“卫星安全模式”、“卫星分块开图”和“自然奇观安全模式”，分别跳过一次性全图探索、按回合揭示地块和跳过电影弹窗锁。不修改 AI 或胜利条件。

2026-10-03 审计修正：后备信条复用原版成长/边界图标，缺少 atlas 时隐藏图标并保留选择；刷新按信条 ID 恢复选择，失效候选和重复确认不发送操作。自然奇观安全替换现在按 vanilla 的 context 初始化/关闭生命周期注册监听，重载先注销再绑定，关闭时不会遗留旧监听。主要文明/城邦列表、集合读取、地图尺寸、未知卫星 schema 和共享预算标记均有失败隔离；不完整城市/单位计数明确写 `objects_complete=false`，未知城邦数写 `UNKNOWN`。Research 的最新离线回归以其 README 和 `tests/README.md` 为准，审计详情见 `docs/16-full-audit-20261003.md` 和 `docs/17-api-contract-audit-20261003.md`；没有新增原生崩溃或性能验收。

日志重点：

2026-10-08原生专项修复了气候事件表的userdata类型识别。实际卫星全2280格探索、未完成队列保存重载续算及重复完成事件去重通过；海平面调试事件造成19格淹没，地图与首次观测属性重载保持。计时优先用原生Automation.GetTime；500格批次实测3.000ms，相同读数标记below_clock_resolution，回退os.clock时注明分辨率UNKNOWN。卫星/万神殿及分支证据见[专项记录53](../Civ6_GrandCampaign_Research/docs/53-native-timing-and-stability-20261008.md)。

新增[原生记录56](../Civ6_GrandCampaign_Research/docs/56-natural-wonder-and-fuel-native-20261008.md)：普通自然奇观真实发现、原版ESC、实际单位移动、推进及保存严格重载通过；真实单位燃料消耗使CO2累积，自然气候升至等级3、第28回合首次SEA_LEVEL、第39回合实际21格低地淹没。煤库存补给为测试夹具，未改气候/排放/阈值；不代表自然经济或大地图性能。用户手动操作游戏前未完成该自然气候终态保存重载；实体Chooser/视觉与目标规模仍待。

- 地图脚本、地图尺寸、格子数、游戏速度；
- 存活主要文明/城邦、主要文明城市数和单位数；
- 万神殿总数、已占用数和可用数；
- 万神殿成立、自然奇观发现、地球卫星项目完成事件；
- 事件是否在当前运行环境的 Gameplay context 中可注册。
- 开启 `GMS_DEBUG_TIMING` 后，每 5 回合快照的扫描耗时和主要文明/城市/单位数量。
- `GMS_SNAPSHOT_OBJECT_BUDGET` 默认限制每次快照最多遍历 10000 个主要文明城市/单位对象，最大 100000；超限时记录 `objects_complete=false` 并停止诊断遍历。
- 开启 `GMS_CLIMATE_DIAGNOSTICS` 后，每个游戏回合一次记录 `GameClimate` 的海平面点数、气候等级、首次海平面事件、下一次上升回合和淹没计数。

后备池使用原版已经存在的低强度成长/边界扩张效果，只扩充唯一信条数量。UI 过滤通过 `ReplaceUIScript` 实现，可能与其他替换 PantheonChooser 的 UI 模组冲突；与Endgame/TestFlow的小局组合已实际成立普通和后备万神殿并保存重载；与其他替换模组的兼容性仍待。

使用前先复制/保存原有存档。Round 1 的目标是取得 `Database.log`、`Lua.log`、`Modding.log` 和测试步骤，不能把本模组日志本身当作崩溃修复。

`GMS_DEBUG_TIMING` 默认关闭；开启后只增加有界快照计时日志，不改变游戏规则。日志用于比较无模组、稳定性模组和组合配置的同一存档回合成本。

`GMS_SNAPSHOT_OBJECT_BUDGET` 默认值为 10000，上限为 100000。每个主要文明城市或单位对象消耗一个预算；零/负数夹到 1，非有限或非法值回到默认值，小数向下取整。预算耗尽时只截断诊断计数，不改变游戏规则；`objects_complete=false` 的快照不得当作完整对象总数或原生性能验收。

`GMS_SATELLITE_CHUNKED_MODE` 默认关闭。每个文明的队列、游标和完成标记保存在玩家属性中；所有队列每个游戏回合共享 `GMS_SATELLITE_CHUNK_SIZE` 个地块检查预算，轮转处理。读档保留本回合预算，完成标记阻止重复入队。探索使用原版海盗场景的 `ChangeVisibilityCount(index, 0)` 调用，不增加持续视野计数；独立普通游戏原生实测全2280格已探索、只有25格当前可见，未完成队列跨重载续跑通过。

2026-10-08独立标准小局实际完成卫星：每回合500格至全2280格探索，仅25格当前可见；完成点及未完成游标500均保存重载通过，后者继续到2280。开启GMS_DEBUG_TIMING也记录satellite_chunk_timing的实际批次成本。V3安全优先及V4原版分支也已真实完成并继续回合通过。具体原生证据和剩余验收见[记录53](../Civ6_GrandCampaign_Research/docs/53-native-timing-and-stability-20261008.md)。

两种卫星开关同时开启时，`GMS_SATELLITE_SAFE_MODE` 优先，分块任务暂停。地图、可见性或存档属性不可用时不继续揭示；已完成项目和科学胜利链保留。离线行为测试在研究仓库运行 `npm ci --ignore-scripts`、`npm test`，不代替游戏内测试。

`GMS_CLIMATE_DIAGNOSTICS` 默认关闭。开启后只调用原版 `GameClimate.GetClimateChangeForLastSeaLevelEvent()`、气候等级/来源、下一次海平面上升/冰损失和淹没计数 getter；首次观测到非负海平面点数时把回合、点数和匹配的 `RandomEvents` 索引写入游戏属性。没有可靠 getter、事件表或属性写入时记录 `UNKNOWN`/失败并继续游戏，不修改气候、地图、随机事件或 UI。该诊断没有专用海平面事件订阅，首次事件按 `PlayerTurnStarted` 的每回合观测对齐。

2026-10-09 当前中间版本统一静态预检已通过（Lua669/669、331编译、MCP209/209）；没有新增实机结论，最终交付门禁仍待。旧测试契约修复与完整日志见Research[记录60](../Civ6_GrandCampaign_Research/docs/60-intermediate-static-integration-20261009.md)，修改前后恢复点见PROJECT。


2026-10-08万神殿专项：三个AI自行成立普通信条；原生受控占用普通池后，人类及AI成立后备信条，粮食4→6.1953125、成长倍率1.09765625及保存重载保持。全池耗尽后原生过滤零候选且仍可推进；两个64px图标atlas存在。普通池占用由原版场景接口建立，不能代替多文明长期规模验收；Chooser实体视觉/点击与API未知状态的原生场景仍未完成。见[记录53](../Civ6_GrandCampaign_Research/docs/53-native-timing-and-stability-20261008.md)。

