# 项目状态：Civ6 GrandCampaign Endgame

## 当前目标


完成附庸与终局玩法的最小可玩闭环：先修复指标/持久化一致性，再接通经原生验证的城市移交、复国、确认操作 UI 与读档恢复。当前只读总览和演练版本不等于完整玩法可玩。

## 要求

- 只修改必要文件；重要旧版本保留在 `Civ6_GrandCampaign_Backups` 和 Git 标签中。
- 所有脚本、XML、JSON、PowerShell 和文档保持显式 UTF-8。
- 原生城市转移、胜利接口和真实保存/读档行为必须经过游戏内验证后才能宣称可用。
- 总览入口追加到共享 LaunchBar，不能替换或重排其他模组按钮。
- AI 军事生产必须区分战前准备和战时动员，优先使用原生 AI 策略、伪收益、城市事件和战争行动配置；默认关闭、有上限，不能未经原生验证直接刷单位。

## 关键决策

- 总览入口和面板沿用已被游戏进程识别过的 `EC_OverviewLaunchUI`/`EC_OverviewPanelUI` action ID，分别使用 30000/30001 的较晚 LoadOrder；确认弹窗和指标桥继续使用原有 action ID，降低进程内重新启用时的 action 清单缓存风险。
- 总览面板只读；未知附庸、文明身份、阶段和接口能力不显示为已知结果。
- 玩家身份 getter 统一通过安全读取；异常身份使本次快照跳过，不生成不完整指标。
- AI 参考代码只保存在 `C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war`；未完成 Schema、离线门控和许可证审查前，不作为运行时依赖。

## 当前进度


- 2026-10-07 已落实离线开发：觉醒记录与UI统一至唯一单人人类槽位，按回合缓存所有者；非0号人类、重建和多人写入拦截回归通过，旧槽位冲突暂停且不删除记录。
- 总览新增统计数据等待/有效/过期/未知状态及候选原因/层级中英文本；城市事务增加 adapter 完整性、坐标/人口/原始所有者的前后核对。
- 真实 adapter、城市ID映射/完整保存、操作 UI 与原生胜利拦截仍是开发阻塞；不能称为除了实机检验外全部完成。
- 本轮静态构建优先，不启动游戏、不加载存档、不推进回合。实现与边界见 [离线交付](../Civ6_GrandCampaign_Research/docs/43-offline-development-20261007.md)。

### 既有记录（截至本轮前；当前结论以上文为准）

- 当前最新轮次为 R134：Endgame UI 合同、总览数据链和 LaunchBar 原生资产合同继续有效；static-first / MCP 构建手册和统一静态门槛继续有效。原生 UI 渲染和事务 adapter 仍未宣称完成。

- Gameplay、总览 UI、确认 UI 和指标桥接已实现。
- 已有 `ReadPlayerID` fail-closed 边界和不完整快照拦截；本轮修正战争观测的身份失效标记被覆盖问题。
- Gameplay 最新回归 150/150；AI 生产边界回归 5/5；UI 最近回归总览 47/47、确认弹窗 19/19、统计桥接 15/15；Research 全套离线回归为499/499，44个 Lua 文件编译通过。
- 入口在玩家身份或工具栏尚未就绪时等待载入/玩家变更/本地回合，成功后注销重试；入口和面板卸载时清理自己的实例、监听和弹窗。
- 本轮六项加载/卸载回归在旧源码上全部失败，修复后通过；原生组合布局尚未验收。
- 重新对照本机 Haikesi、Steam 原版及公开 UI 框架，保留共享容器追加方案；未新增框架依赖或修改第三方 UI。
- 2026-10-04 修复只读接口诊断仅在建城前运行的问题：未观察到城市时按五回合采样补查，最多额外四次；字段读取异常或非函数成员不能中断诊断。
- 旧日志中的 `TransferCity` 等名称只是候选 adapter 签名，不是本机原生能力证据；当前安装资产扫描与 MCP 只读探针均未确认标准城市转移/附庸操作。开局零城市记录也不证明失去最后城市后存活，正式归还仍待原生核对。
- 共享工具栏入口的实例创建、尺寸通知和局部失败现在会回滚自身控件，重试不会留下半个按钮或重复追加。
- 常用玩家、地图、配置、事件和集合成员读取增加受保护的可调用性检查；数据库代理仍保留原生索引/迭代访问。
- 左上角入口在本地化暂不可读时使用“附庸总览/附庸”中文兜底，不把 `LOC_EC_*` 键名显示给玩家。
- 入口在 `LoadScreenClose` 之后共享工具栏才出现时，还会监听原生 `GameCoreEventPublishComplete`，同一回合完成刷新即可补挂；对应回归已覆盖，成功后注销重试监听。
- 入口现在在注册 `SetInitHandler` 后立即执行一次受保护初始化，并额外监听 `VisualStateRestored`；这样热重载时即使 LaunchBar 的首次就绪事件已经错过，也能在当前上下文尝试挂载，成功后仍只保留一个入口。
- 总览面板对共享 `EC_OverviewModel` 的导入采用受保护调用；热重载或 action 顺序导致模型暂不可见时降级为只读不可用状态，不让总览面板 context 连带阻止左上角入口。
- 总览面板刷新前验证模型返回结构；`nil`、缺少 `Entries` 或损坏行会保持只读不可用/可读占位，不让异常逃出 UI 回调。
- 入口视觉改为原版/Haikesi 同款的城邦图标按钮，避免把“附庸”文字直接塞进共享工具栏造成并排重叠；中文名称仍由悬停提示提供。
- Endgame 的总览入口/面板 action 保留旧 ID 并使用 30000/30001，让共享 ButtonStack 的追加顺序在常见 UI action 之后再执行；实际组合仍以原生日志和画面为准。
- 城市攻占观测的坐标查询与城市所有者读取现在都在 fail-closed 边界内，地图初始化或读档恢复阶段的原生异常只会放弃本次证据；入口上下文加载时还会写入 `overview_launch_context_loaded` 诊断标记。
- 入口在共享 ButtonStack 已存在时立即追加；`LoadGameViewStateDone` 仅作为缺栈重试，避免较晚 action 错过一次性事件。其他模组仍可在后续继续往共享栈尾追加，实际排列以综合测试为准。
- 上述入口在 `isReload=true` 的热重载路径会直接复用已经创建的共享工具栏顺序，不等待已经错过的一次性视图事件，避免停用/再启用模组后按钮要等到下一回合才出现。
- 入口清理现在即使当前没有进入等待态也会注销已经绑定的视图事件，重复热重载不会积累隐藏回调。
- 共享入口实例创建或尺寸通知失败时，现在会销毁自身半成品并立即按剩余 ButtonStack 重算背景宽度，重试等待期间不会留下过宽的空白背景；新增失败回滚回归。
- 总览面板的原生输入对象回调已修正：`SetInputHandler(..., true)` 与 `GetMessageType()`/`GetKey()` 配套，ESC 不再按两个普通参数误读。确认弹窗也统一采用该接法，并保留旧双参数兼容；同时修正觉醒状态读取固定使用玩家槽位0的问题，改为当前本地人类玩家槽位；相关离线回归为总览46/46、确认19/19，最新完整基线498/498。
- 输入对象注册参考本机原版 `TechCivicCompletedPopup.lua` 和 CQUI。确认弹窗仅在 active 时消费输入；未确认第二个 `true` 参数的输入优先级含义，不将其解释为高优先级捕获。实机 ESC/Enter 和窗口关闭后的地图输入仍待综合测试。
- 2026-10-04 已冻结 AI 爆兵新增需求：战前提高军用单位/军营/城防生产倾向，战时提高补充、升级、攻城支援和防御行动；先在 Research 中完成 `AiLists`/`AiFavoredItems`/`AiOperationDefs` Schema 审计，再做默认关闭的最小 SQL slice。
- 2026-10-05 Round 77 依据 RHAI `DefaultSavings=3` 与 `AggressiveSavings=-2`，把已有 `STRATEGY_STRENGTH_ADV`/`STRATEGY_AT_WAR` 的 `SAVING_UNITS` 调低为 3/-2；不复制 GoldenAge 在本机没有原生映射的全单位购买成本类型。
- 2026-10-04 已接入第一版默认关闭的 AI 军事生产切片：`EC_AI_MILITARY_PREWAR` 为 +15，`EC_AI_MILITARY_WARTIME` 为 +35 且受 Steam 原生 `REQUIREMENT_PLAYER_AT_WAR_AND_HAS_MET` 约束；Lua 只绑定存活主要 AI，属性状态、失败重试上限和观测模式保护均已覆盖。
- 2026-10-04 Round 10 已接入同一 criteria 门控的 `Data/EC_AIMilitaryDoctrine.sql`：提高原生战前生产/军用城市专精、常备军伪收益，扩大基础/战时攻城防御行动槽，提高战时攻城和 `Upgrade Units` 触发优先级；不直接生成单位，默认仍关闭。
- 2026-10-04 Round 11 已在同一 doctrine SQL 中加入原生维护费折扣：AI 基础 +1，研究 `TECH_MILITARY_ENGINEERING` 后再 +1，高难度 AI 再 +1；三项均绑定原版 AI requirement，理论上限为每单位 +3，原版 XML + Gameplay schema dry-run 已通过。
- 2026-10-04 Round 12 已加入城市规模与战略资源门槛：2 城和 5 城分别追加 +5 军用单位生产；拥有铁、马、硝石、煤、石油、铝或铀中的任一资源时，AI 获得额外 +1 单位维护费折扣。城市/资源条件都使用本机原版 RequirementType，默认仍由同一 criteria 关闭。
- 2026-10-04 Round 13 复核原版 RequirementType 时发现旧的 `REQUIREMENT_PLAYER_IS_AT_WAR` 并不存在于本机 Steam 数据；已改为原生 `REQUIREMENT_PLAYER_AT_WAR_AND_HAS_MET`，并让 Research 验证器直接扫描原版 XML 的属性行和子元素行，防止伪原生类型混入。
- 2026-10-04 Round 14 在同一已核对的战争集合上加入 `EC_AI_MILITARY_MAINTENANCE_WARTIME`：AI 处于战争且已知对手时额外获得 +1 单位维护费折扣；基础、科技、高难度、资源和战时五项合计理论上限为 +5，仍由同一 criteria 默认关闭。
- 2026-10-04 Round 15 复用原版 `MODIFIER_PLAYER_ADJUST_UNIT_UPGRADE_DISCOUNT_PERCENT`，给 AI 基础 +10% 升级折扣，战争且已知对手时再 +10%；两项总上限 +20%，促进旧军队升级补充而不是直接生成单位。
- 2026-10-04 Round 16 接入 RHAI 已验证的战时城市事件模式：补充 `STRATEGY_AT_WAR`（0 条件的引擎战争钩子）、`CityEvents` 列表以及 `CITY_EVENT_DEFAULT`/`CITY_UNDER_THREAT` 的 `Upgrade Units` 选择；使用 `INSERT OR IGNORE`，不覆盖其他 AI 模组的同名策略定义。
- 2026-10-04 Round 17 接入 RHAI `DefaultUnitBuilds` 的原生 `UnitPromotionClasses` 模式：为主要 AI 增加近战、远程、攻城、反骑、重骑、支援、海军远程和轰炸机 8 类有界偏好权重，强化能组成攻城编队的持续造兵选择。
- 2026-10-04 Round 18 接入 Steam 原生 `MODIFIER_PLAYER_CITIES_ADJUST_NUM_UNITS_SUPPORTED`：AI 每城基础 +1 支持容量，战争且已知对手时再 +1；与维护费折扣和生产加成配套，理论上限为每城 +2，不直接创建单位。
- 2026-10-05 Round 19 依据 RHAI 的 `STRATEGY_AT_WAR` 设计补充独立战时 `Yields`、`PseudoYields`、`UnitPromotionClasses` 和 `AiBuildSpecializations` 列表；战争激活时提高生产、常备军伪收益、单位组合和军事城市专业化，所有权重有界且仍只作用于 AI。
- 2026-10-05 Round 20 复用 RHAI 的 `STRATEGY_STRENGTH_ADV` 条件入口：AI 满足军力/科技/分数中至少两项且是主要文明时，激活独立战前生产、伪收益、单位组合和军事城市专业化列表；只调整军备偏好，不挂外交或自动宣战行动。
- 2026-10-05 Round 21 为 `STRATEGY_STRENGTH_ADV` 和 `STRATEGY_AT_WAR` 增加 `Buildings`/`Districts` 列表及 `BUILD_CITY_DEFENSES` 偏好：覆盖兵营、马厩、军械库、军事学院、军营和机场；验证器确认 6+6 列表系统与 Steam 原生类型。
- 2026-10-05 Round 22 依据 RHAI 的 `AiOperationTypes`/`PerWarOperationTypes` 模式，为 `STRATEGY_STRENGTH_ADV` 和 `STRATEGY_AT_WAR` 增加独立的攻城/防御行动类型偏好及每战争行动偏好；仅使用原生 `CITY_ASSAULT`、`OP_DEFENSE`，不新增行动或自动宣战。
- 2026-10-05 Round 23 为高难度 AI 增加原生 `PLAYER_IS_HIGH_DIFFICULTY_AI` 的 +5 军用单位生产，并在完成 `TECH_MILITARY_ENGINEERING` 后通过原生科技 requirement 再增加 +5；两项仍受同一默认关闭 criteria 门控，理论新增上限为 +10。
- 2026-10-05 Round 24 为处于已知对手战争且完成 `TECH_MILITARY_ENGINEERING` 的 AI 增加额外 +5 军用单位生产；复用既有战争/科技 requirement，作为战时科技动员 surge，默认关闭且只对 AI 生效。
- 2026-10-05 Round 25 为处于已知对手战争且完成原生 Atomic 时代 `TECH_COMBINED_ARMS` 的 AI 再增加 +5 军用单位生产；这是晚期战争补充 surge，仍默认关闭、只对 AI 生效。
- 2026-10-05 Round 26 为 `STRATEGY_AT_WAR` 和 `STRATEGY_STRENGTH_ADV` 增加原生 `PSEUDOYIELD_CITY_DEFENSES`/`PSEUDOYIELD_CITY_DEFENDING_UNITS` 偏好，分别使用 10/8 与 6/4 的有界权重，强化守城驻军需求而不直接创建单位。
- 2026-10-05 Round 26 post backup 已生成于 `C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round26-city-defense-pseudos-post`，三仓库 bundle、源代码 zip、HEAD 指针和 SHA-256 清单均已验证。
- 2026-10-05 Round 27 明确修正原生 `City Defense` 的 `AiOperationDefs`：绑定 `OP_DEFENSE` 并要求 2 个单位成行动，接通已有战时/战前防御偏好而不新增自定义行动。
- 2026-10-05 Round 28 新增受威胁城市专用 `STRATEGY_UNDER_ATTACK`：使用 `Cities Under Threat >= 1`，提高军用生产、城防/驻军伪收益、军用建筑/区域、单位编制、城防行动和 `Upgrade Units` 城市事件；所有权重有界且仍默认关闭。
- 2026-10-05 Round 29 新增项目命名的 `STRATEGY_EC_MILITARY_LATE`：复用 Steam 原版 `Is Industrial`/`Is Modern` 与 `Is Not Major` 条件，在工业/现代时代提高 AI 生产、军用单位组合、军用建筑/区域、攻城/防御行动和 `Upgrade Units` 偏好；仍由同一 AI 开关控制，不直接创建单位。
- 2026-10-05 Round 30 为 `STRATEGY_AT_WAR` 和 `STRATEGY_EC_MILITARY_LATE` 增加原生 `Technologies` 列表：战争中和晚期优先军事工程、军科、联合武器、先进飞行、核裂变/聚变、隐形、机器人等已确认科技；权重有界，仍默认关闭，不改变科技成本。
- 2026-10-05 Round 31 为 `STRATEGY_UNDER_ATTACK` 增加原生 `Technologies` 列表：城市受威胁时以 4/5 的有界权重优先十项军事科技，继续复用本机 `KIND_TECH` 类型，不改变科技成本或直接生成单位。
- 2026-10-05 Round 32 为 `STRATEGY_STRENGTH_ADV` 增加战前原生 `Technologies` 列表：在军力/科技/分数优势策略激活时以 3/4 的较低有界权重提前研究十项军事科技，补齐战前研究路径。
- 2026-10-05 Round 33 为高难度 AI 增加原生 `PLAYER_IS_HIGH_DIFFICULTY_AI` 支持容量层：每城额外 +1 支持槽，与既有高难度军用生产 +5 配套，理论高难度 AI 每城支持容量上限为基础 +1、战时 +1、高难度 +1。
- 2026-10-05 Round 34 保持运行时爆兵切片不变，Research 新增游戏速度校准验证；原版没有军事生产 `ScaleByGameSpeed` 样例或速度 requirement，Endgame 两个 AI 军事数据文件因此继续 fail-closed。
- 2026-10-05 Round 35 新增有界 `EC_AI_MILITARY_MIDGAME_SURGE`：复用原版军事生产 modifier，Amount=5，仅 AI 生效并限定 `ERA_MEDIEVAL` 至 `ERA_RENAISSANCE`；Lua 绑定器仍默认关闭、失败三次即停止。
- 2026-10-05 Round 36 新增有界 `EC_AI_MILITARY_LATE_SURGE`：Amount=10，限定 `ERA_INDUSTRIAL` 至 `ERA_INFORMATION`，与晚期 AI 策略偏好配套；生产绑定器现在覆盖 10 个 modifier。
- 2026-10-05 Round 37 为 `STRATEGY_EC_MILITARY_LATE` 补齐原生 `PerWarOperationTypes` 列表，按晚期 `AiOperationTypes` 同步偏好 `CITY_ASSAULT`/`OP_DEFENSE`，让晚期战争层拥有每场战争的攻城/防御行动输入；不新增操作定义或自动宣战。
- 2026-10-05 Round 38 为 `STRATEGY_UNDER_ATTACK` 增加原生 `PerWarOperationTypes` 列表，仅偏好 `OP_DEFENSE=2`，让受威胁城市的临战防御输入按战争维度继续生效；不改变全局行动上限。
- 2026-10-05 Round 39 新增 `STRATEGY_EC_MILITARY_BEHIND`：复用原版 `Lags Military=33` 与 `Is Not Major` 排除条件，为军力落后的主要 AI 增加有界生产、军用建筑/区域、单位组合、军事科技、攻城/防御和升级事件偏好；不新增行动或直接生成单位。
- 2026-10-05 Round 40 为军力落后策略增加原生 `Civics` 列表，优先军事传统、军事训练、防御战术、雇佣兵、民族主义、焦土、总动员和快速部署；只在 `STRATEGY_EC_MILITARY_BEHIND` 激活时生效，不改变 civic 成本或前置条件。
- 2026-10-05 Round 41 为 `STRATEGY_AT_WAR` 增加原生 `Civics` 列表，战争期间提高军事传统、军事训练、防御战术、雇佣兵、民族主义、焦土、总动员和快速部署偏好；不改变 civic 成本、前置条件或全局政策规则。
- 2026-10-05 Round 42 为 `STRATEGY_STRENGTH_ADV` 增加原生 `Civics` 列表，使用低于战时层的 2/3/4 权重，让满足军力/科技/分数优势条件的 AI 在战前准备军事政策；不改变 civic 成本、前置条件或和平期全局政策规则。
- 2026-10-05 Round 43 为 `STRATEGY_STRENGTH_ADV` 增加原生 `CityEvents` 列表，在战前强势策略下优先 `Upgrade Units`；不改变升级折扣、单位成本或直接生成单位。
- 2026-10-05 Round 44 为 `STRATEGY_EC_MILITARY_LATE` 增加原生 `Civics` 列表，以低于战时层的 3/4/5 权重偏好晚期军事政策；不改变 civic 成本、前置条件或全局政策规则。
- 2026-10-05 Round 45 为 `STRATEGY_UNDER_ATTACK` 增加原生 `Civics` 列表，以 5/6/7 的有界权重偏好防御、焦土、总动员和快速部署；只在城市受威胁策略激活时生效。
- 2026-10-05 Round 47 依据独立保存的 Late Game AI 8.29 代码证据，新增 `CIVIC_MOBILIZATION` 与 `CIVIC_RAPID_DEPLOYMENT` 两条 AI-only `REQUIREMENT_PLAYER_HAS_CIVIC` 军用生产门控，各为 +5；Lua 绑定器覆盖 12 个 modifier，默认开关、属性状态和失败上限保持不变。
- 2026-10-05 Round 48 依据 Late Game AI 的 `GAME_SPEED_TYPE` criteria 结构，为 Online/Quick/Standard/Epic/Marathon 分别加载 +4/+5/+7/+10/+15 的 AI 军用生产 modifier；每个 speed action 同时要求 `EC_AI_MILITARY_PRODUCTION_TEST=1`，不使用未经证实的 `ScaleByGameSpeed`。

## 下一步


- 离线状态/统计/事务修复已完成；先取得原生城市移交和玩家生命周期依据，再完成单城市 adapter、城市ID/完整保留映射、复国语义与确认操作 UI。
- 按[可玩验收方案](../Civ6_GrandCampaign_Research/docs/42-playable-acceptance-20261007.md)依次做最小实机验收。真实效果、胜利策略和大地图性能在核心路径通过后验证；不再以新增静态通过项代替玩法完成。
- 用户已有日志只作既有证据；助手不自行启动、读档或推进游戏。

### 既有记录（截至本轮前；当前结论以上文为准）

- 重新载入并核对 `EC_OverviewLaunchUI`/`EC_OverviewPanelUI`；日志仍没有总览上下文时，用新进程排除清单缓存。
- 在用户的多模组组合中确认左上角入口、按钮顺序、中文文本、打开/关闭、回合推进和读档幂等。
- 只有原生日志和实际存档验证通过后，才评估真实附庸移交/归还接口。
- 继续核对 `REQUIREMENT_PLAYER_HAS_CIVIC` 的原生运行时评估，以及总动员/快速部署 civic 生产层与战时、时代、科技生产层的叠加；当前没有游戏内证据，不能据此宣称真实爆兵增量。
- 继续在五种游戏速度的相同存档中比较生产队列、单位数、军力和回合耗时；速度 action 已通过静态合同，但真实 criteria 选择和 modifier 叠加仍需原生回合验证。
- 继续完成 AI 游戏速度校准、资源/升级 requirement、`PLAYER_IS_HIGH_DIFFICULTY_AI`/科技生产门槛、战时军事工程与 Combined Arms 动员 surge、工业/现代时代 `STRATEGY_EC_MILITARY_LATE` 的原生回合验证、战时/晚期 `Technologies` 与晚期 `Civics` 路径、受威胁城市 `STRATEGY_UNDER_ATTACK` 的 Civics/科技列表、强势战前 `STRATEGY_STRENGTH_ADV` 科技/Civics/CityEvents 路径、军力落后 `STRATEGY_EC_MILITARY_BEHIND` 的条件与 `Civics` 刷新、城市防御伪收益、`STRATEGY_UNDER_ATTACK` 的临战条件刷新、`STRATEGY_STRENGTH_ADV`/`STRATEGY_AT_WAR` 的条件刷新、城市事件/战时列表、军营/城防建筑列表、攻城/防御行动类型偏好、`AiOperationDefs` 城防门槛、`UnitPromotionClasses` 偏好、高难度支持容量、晚期每场战争行动偏好、临战每场战争防御行动偏好和战争结束退出滞后的原生回合验证；当前生产加成与 doctrine 选项保持同一高级设置且默认关闭，不把第三方 AI 模组整包合并。战争 requirement 现在明确包含“已知对手”条件，战前/战时/临战/军力落后/晚期生产列表、科技与 civic 偏好、维护费、升级折扣、城市事件、建筑/区域、行动类型、单位组合偏好、军事城市专业化、支持容量、晚期和临战 `PerWarOperationTypes` 切片已加入。
- 下一会话从 Research 的 `docs/23-handoff-20261004.md` 开始；Research 不启用，先验证当前进程是否发现总览 action，再处理用户日志中的新问题。

## 未解决问题


- 完整可玩发布仍被真实附庸/城市归还/复国与原生胜利策略阻塞；模拟事务 adapter 测试不能证明原生可执行。
- 旧非0人类存档的觉醒槽位冲突迁移、完整输入/视觉验收、原生存读档单次结算和后期性能仍待完成。

### 既有记录（截至本轮前；当前结论以上文为准）

- 尚无本轮最新进程对总览 action、保存/读档和真实城市操作的原生证据。
- `REQUIREMENT_PLAYER_HAS_CIVIC` 的引擎评估与两个 civic-gated 军用生产 modifier 的真实效果尚未在原生游戏回合验证；当前只有成熟模组代码对照、Steam civic 类型检查和离线 SQL/Lua 合同。
- 五个 `GAME_SPEED_TYPE` criteria 的原生选中时点、速度专用 +4/+5/+7/+10/+15 的实际生产效果及与时代/战时层叠加尚未在游戏内验证；当前仅有成熟项目结构证据和 modinfo/SQL 离线合同。
- 部分 gameplay getter 在原生环境不可用时仍显示 UNKNOWN，这是设计上的安全结果。
- Research 现已提供 `tools/validate_project.py` 与 `schema/project.schema.json`，对四个 PROJECT.md 的恢复字段执行结构化 schema 校验；运行时真实性仍单独按静态/实机边界记录。
- AI 战略/行动入口、不同版本 RHAI/BAIT 的兼容性和真实回合爆兵效果尚未在原生游戏中验证。
- AI 生产 modifier 的原生绑定时点、战争/高难度/科技、军事工程与 Combined Arms surge requirement 的实际评估和对升级/行动选择的影响尚未在原生游戏中验证；当前实现没有直接生成单位。
- AI doctrine 的原生 `StrategyConditions`、工业/现代时代 `STRATEGY_EC_MILITARY_LATE`、战时/晚期 `Technologies` 列表、`STRATEGY_UNDER_ATTACK`/`STRATEGY_STRENGTH_ADV`/`STRATEGY_AT_WAR` 条件刷新、`AiFavoredItems`、城市防御伪收益、建筑/区域偏好、行动类型偏好、`City Defense` 的 `OP_DEFENSE`/2 单位门槛、临战/晚期 `CityEvents`/`Upgrade Units` 选择、战时列表、`UnitPromotionClasses` 权重、军事城市专业化、支持容量、行动并发、攻城优先级、升级触发优先级、城市数生产门槛、资源/战时维护费、升级折扣和 at-war-and-has-met 的评估时点尚未在原生回合验证；游戏速度没有找到生产 modifier 的直接 RequirementType，当前只保留数据校准；战争结束后的退出滞后仍未实现。
- 游戏速度校准器已确认当前原版军事生产没有 `ScaleByGameSpeed` 参数，也没有可直接复用的速度 requirement；若后续增加时代窗口，必须用独立 `StartEra`/`EndEra` 实验并保持默认关闭。实际速度倍率、AI 生产队列和战争结束退出滞后仍未在原生回合验证。
- 中期时代窗口的实际生产效果、与战时 +35/科技 surge 的叠加、AI 单位数量和战争结束退出滞后仍未在原生回合验证。
- 晚期 +10 与中期/高难度/科技/战时 surge 的实际叠加、后期 AI 单位数量、滚雪球速度、回合耗时和战争结束退出滞后仍未在原生回合验证。
- 晚期 `PerWarOperationTypes` 是否会按每场战争提高攻城/防御行动创建、与基础 `AiOperationTypes` 的叠加方式及其对回合耗时的影响仍未在原生回合验证。
- `STRATEGY_UNDER_ATTACK` 的 `OP_DEFENSE` 每场战争偏好是否会按受威胁城市刷新、与临战基础行动列表叠加及影响行动并发仍未在原生回合验证。
- `STRATEGY_EC_MILITARY_BEHIND` 的 `Lags Military=33` 刷新时点、与强势/战时/临战策略的叠加以及是否能让落后 AI 恢复军力仍未在原生回合验证。
- 军力落后策略的 `Civics` 偏好是否会按 civic 前置链和时代正确刷新、是否压过经济/外交 civic 以及对军队恢复的实际贡献仍未在原生回合验证。
- 战时 `Civics` 偏好是否只在战争策略激活时生效、与军力落后/晚期 civic 列表如何叠加以及对政策槽和生产队列的实际影响仍未在原生回合验证。
- 强势战前 `Civics` 偏好是否按 `STRATEGY_STRENGTH_ADV` 的两项条件正确刷新、与经济/外交 civic 竞争及对战前生产队列的实际影响仍未在原生回合验证。
- 强势战前 `CityEvents` 的 `Upgrade Units` 是否按策略刷新、与原版城市事件竞争以及对旧军队升级/战前军力的实际贡献仍未在原生回合验证。
- 晚期 `Civics` 偏好是否按工业/现代条件正确刷新、与战时/军力落后 civic 列表叠加及对晚期生产队列的实际影响仍未在原生回合验证。
- 临战 `Civics` 偏好是否按 `Cities Under Threat >= 1` 正确刷新、与战时/晚期/军力落后列表叠加及对受威胁城市生产队列的实际影响仍未在原生回合验证。

## Round 49：前置军事 civic 分阶段生产门控

- `Data/EC_AIMilitaryProduction.xml` 新增六个 AI-only `REQUIREMENT_PLAYER_HAS_CIVIC` 门控，覆盖军事传统、军事训练、防御战术、雇佣兵、民族主义、焦土；生产增量为 +2/+2/+3/+3/+4/+4，按原生 civic 前置链自然递进。
- `GamePlay/EC_AIMilitaryProduction.lua` 的幂等绑定器扩展到 18 个 modifier，仍默认关闭、只处理存活主要 AI、保留三次失败上限和 UNKNOWN fail-closed。
- 不修改 civic 成本、前置条件、政策槽、人类玩家或直接刷单位；实际 civic requirement 评估、生产叠加和爆兵增量仍需原生回合验证。

Round 49 提交：Endgame `5229244`，Research `2ccb7e8`；编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round49-prewar-civic-military-production-pre`；post 备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round49-prewar-civic-military-production-post`。


## Round 50：战略资源条件军事生产

- `Data/EC_AIMilitaryDoctrine.sql` 新增 `EC_AI_MILITARY_PRODUCTION_RESOURCE`，复用原生 `MODIFIER_PLAYER_CITIES_ADJUST_MILITARY_UNITS_PRODUCTION`，金额为 +2。
- 该 modifier 同时要求 `PLAYER_IS_AI` 和既有 `EC_AI_MILITARY_RESOURCE_ANY`；AI 拥有铁、马、硝石、煤、石油、铝或铀任一资源时才获得这层小幅军用单位生产增量。
- 不改变资源数量、交易、单位成本或人类玩家规则；资源 requirement 与维护费层共享集合但使用独立 modifier，避免重复绑定。
- 本轮没有把未验证的 Workshop/BAIT/RHAI 代码复制进运行时；公开 Steam 页面处于未登录状态，目标 Workshop 下载未确认。

Round 50 编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round50-resource-production-pre`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round50-resource-production-post`。原生游戏回合仍未验证，下一步需要比较拥有/缺少战略资源的 AI 生产队列、单位数与军力。


## Round 51：战时战略资源补充生产

- 在 R50 的和平期资源生产层之上，新增 `EC_AI_MILITARY_PRODUCTION_WARTIME_RESOURCE`，使用原生 `MODIFIER_PLAYER_CITIES_ADJUST_MILITARY_UNITS_PRODUCTION`，Amount=4。
- 所有者要求复用 `EC_AI_MILITARY_WARTIME_OWNER`（AI 且处于已知对手战争），主体要求复用 `EC_AI_MILITARY_RESOURCE_ANY`；因此只有拥有铁、马、硝石、煤、石油、铝或铀的战时 AI 才获得这层补充。
- 不修改资源、单位成本、战争外交或人类玩家规则；这是已有战争生产层上的条件化补充，不直接生成单位。
- R51 编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round51-wartime-resource-production-pre`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round51-wartime-resource-production-post`。


## Round 52：战时信息时代轰炸机生产

- `Data/EC_AIMilitaryDoctrine.sql` 新增 `EC_AI_MILITARY_WARTIME_AIR_BOMBER`，复用原生 `MODIFIER_PLAYER_CITIES_ADJUST_UNIT_TAG_ERA_PRODUCTION`。
- 该层要求 `EC_AI_MILITARY_WARTIME_OWNER`，并以 `UnitPromotionClass=PROMOTION_CLASS_AIR_BOMBER`、`EraType=ERA_INFORMATION`、`Amount=20`、`Extra=-1` 限定范围；只强化已知战争中的信息时代 AI 空军补充。
- 设计参考 RHAI `AI_INFO_AIR_BOOST` 的同一原生 modifier 结构，但金额更低且增加战时门控；不直接生成单位、不修改人类玩家或空军成本。
- R52 编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round52-wartime-air-production-pre`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round52-wartime-air-production-post`。


## Round 53：BAIT 公开页面证据固化

- 通过 Steam Workshop 公开页面核对到 BAIT 的设计声明：战争承诺、定期补充、多个城市攻势、城防/军营/军事学院优先和受攻击后的总动员；页面同时明确反对只堆平坦 AI 数值。
- 证据文件已保存到 `C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\3256128675-BAIT-public-page-20261005.md`，并加入参考目录 `MANIFEST.md`/`SHA256SUMS.txt`。
- 这轮不新增运行时 modifier；Endgame 已有的战时生产、PerWarOperations、CityEvents、军用建筑/区域和空军切片继续与公开设计方向对齐。
- 页面仍处于未登录状态，未取得 BAIT 代码，不能把页面描述当作 SQL/Lua 证据。

## Round 54：高难度生产缩放审计

- 核对本机 Steam `Leaders.xml` 后确认原版已有 `HIGH_DIFFICULTY_PRODUCTION_SCALING`：主要文明 trait、`PLAYER_IS_HIGH_DIFFICULTY_AI`、`MODIFIER_PLAYER_CITIES_ADJUST_CITY_YIELD_MODIFIER`、`YIELD_PRODUCTION` 和 `LinearScaleFromDefaultHandicap` 均为原生结构。
- Late Game AI 8.29 的 `Core.sql` 与五档速度 SQL 也证明了同一难度缩放类型可用于军用单位生产；但其 Quick/Marathon 数值不能直接复制，因为当前项目已经叠加原版全城生产、项目高难度 +5、速度、时代、战争、资源和 civic 层。
- R54 不新增动态军用生产 modifier，保留默认关闭总开关和现有固定 +5；独立证据保存于 `C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-LateGameAI-difficulty-scaling-20261005.md`，供后续可替换式实验使用。

R54 编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round54-difficulty-scaling-audit-pre`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round54-difficulty-scaling-audit-post`。本轮无运行时代码变更，实际难度数值、层叠生产和 AI 单位增量仍需原生回合验证。

## Round 55：战时和平偏好与战争承诺

- `Data/EC_AIMilitaryDoctrine.sql` 新增 `EC_AI_MILITARY_AT_WAR_DIPLOMACY`，挂到原生 `STRATEGY_AT_WAR` 的 `DiplomaticActions` 系统。
- 仅对已处于战争状态的 AI 关闭 `DIPLOACTION_MAKE_PEACE`（Favored=0, Value=-25）和 `DIPLOACTION_PROPOSE_PEACE_DEAL`（Favored=0, Value=-50）的偏好；不自动宣战、不禁止和平、不修改人类玩家外交。
- 设计依据是 BAIT 公共页面的战争承诺描述和 RHAI 的成熟 `DarwinistEnjoysWarDiplomacy` 结构；目的是让战时生产/补充窗口不因廉价和平过早结束，权重保持有界。

Research 验证器新增原生 `DiplomaticActions.xml` 类型检查，AI doctrine focused 结果为 `at_war_lists=11`。Round 55 编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round55-wartime-peace-commitment-pre`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round55-wartime-peace-commitment-post`。和平接受、战争持续时间和生产增量仍需原生回合验证。

## Round 56：战前强势策略来源审计

- 外部 RHAI 固定代码确认当前 `STRATEGY_STRENGTH_ADV` 的条件和列表结构有成熟项目依据；当前 Endgame 运行时实现保持不变。
- RHAI 的 `STRATEGY_WAR_IF_STRONG` 同时包含 `Major Civ Wars` 和战争姿态列表，本轮不直接接入，避免把战前爆兵实验扩大为未经验证的战争进入行为或重复权重。
- 研究证据与 Git/压缩包备份已保存；Round 56 post backup 将生成于 `C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round56-strength-strategy-audit-post`。现有策略条件刷新、列表叠加、生产队列和战前单位增量仍需原生回合验证。

## Round 57：战时 City Defense 编制门槛

- Endgame doctrine 新增原生 `OpTeamRequirements`：City Defense 至少 2 个战斗单位、1 个远程单位，最大分别为 8 和 7；这沿用 RHAI 的成熟配置，作用于 AI 防御行动编组。
- 既有 `OP_DEFENSE`、`MustHaveUnits=2`、战时/临战城市事件和生产层保持不变；本轮没有直接刷单位或扩大人类规则。
- 实际受威胁城市刷新、行动组队和生产队列效果尚未在原生回合验证。

Round 57 pre backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round57-city-defense-team-requirements-pre`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round57-city-defense-team-requirements-post`。提交为 `04cdcba052e4c7c9bf92ee9f611c78deab9051b1`。


## Round 58：战时 City Attack 编制门槛

- Endgame doctrine 新增原生 `OpTeamRequirements`：City Attack Force 至少 3 个近战、3 个攻城、2 个攻城全类单位，最大分别为 8、5、6；来源是 RHAI 的成熟攻城编组配置。
- 现有 `Wartime Attack Walled City`、战争条件、行动上限和生产层保持不变；本轮只提高已有攻城行动的组队需求，不直接刷单位。
- 实际战争攻城刷新、单位编组和生产队列效果尚未在原生回合验证。

Round 58 pre backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round58-city-attack-team-requirements-pre`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round58-city-attack-team-requirements-post`。

## Round 59：战时攻城队伍强度门槛

- Endgame doctrine 复用 RHAI 的两个原生 `AiOperationTeams` 调整：`Wartime Attack Enemy City` 为 `Initial=-1, Ongoing=0.5`，`Wartime Attack Walled City` 为 `Initial=-10, Ongoing=-0.5`。
- 这让已有战争行动更早组建攻城队伍，与 R57/R58 的编制需求一起推动补兵；战争门控、行动定义和单位成本保持不变。
- 实际队伍刷新、攻城频率、单位损耗和回合性能尚未在原生回合验证。

Round 59 pre backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round59-wartime-operation-team-thresholds-pre`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round59-wartime-operation-team-thresholds-post`。

## Round 60：沿海战争海军编制门槛

- Endgame doctrine 复用 RHAI 的原生 `City Naval Attack Force` 编制：作战单位 6-14、舰船 3-12（比例 0.6-1）、近战 2-7、远程 0-7。
- 沿海战时无墙/筑墙行动的 `InitialStrengthAdvantage` 为 -10，持续门槛为 0.1/0.2；不引入自定义海军 team 或新行动。
- 实际沿海战争队伍、舰船损耗和生产队列效果尚未在原生回合验证。

Round 60 pre backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round60-naval-attack-team-requirements-pre`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round60-naval-attack-team-requirements-post`。

## Round 61：Naval Superiority 战时门控

- Endgame doctrine 复用 RHAI 的 Naval Superiority 配置：`EnemyType=WAR`、`MustHaveUnits=3`、`MinOddsOfSuccess=0.25`，队伍强度 `Initial=-2, Ongoing=0.6`。
- 队伍要求舰船 3-9、近战 1-5、远程 1-6；和平期不再无条件维持该行动的海军需求。
- 实际战争门控、舰船损耗和海军生产队列效果尚未在原生回合验证。

Round 61 pre backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round61-naval-superiority-war-gate-pre`；Endgame 提交 `4b08be0`，Research 提交 `71fcee1`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round61-naval-superiority-war-gate-post`。

## Round 62：战时 Naval Superiority 策略接线

- 修复 R61 的策略接线缺口：原生 `Operations.xml` 注释说明 `NAVAL_SUPERIORITY` 必须由策略提高后才使用；现将它加入 `STRATEGY_AT_WAR` 的 `AiOperationTypes` 与 `PerWarOperationTypes`，值均为 1。
- 新增 `PerWarOperationsLimits/NAVAL_SUPERIORITY=1`，保留原生基础上限 1，形成每场战争一次的有界海军优势行动需求。
- 依据 RHAI `Strategies/Naval.sql` 的 `NavalPerWarOperations`；不新增行动、不自动宣战、不直接生成单位、不改变单位成本。

Round 62 pre backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round62-naval-strategy-operation-hook-pre`；Endgame 提交 `843fd85`，Research 提交 `ec5df50`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round62-naval-strategy-operation-hook-post`。原生行动刷新、海军补兵、损耗和回合性能仍需 A/B 验证。

## Round 63：基础城市攻城行动上限

- 依据 RHAI `Ops.sql`，将原生 `BaseOperationsLimits/CITY_ASSAULT` 从 2 提高到 3；`OP_DEFENSE` 保持 2，每战攻城上限保持 2。
- 这增加 AI 战前/战时可同时维持的原生攻城承诺，单位仍通过正常城市生产和补兵形成；不新增行动、不自动宣战、不直接生成单位、不改变单位成本。
- 研究证据：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-base-city-assault-cap-audit-20261005.md`。

Round 63 pre backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round63-base-city-assault-cap-pre`；Endgame 提交 `38da2e9`，Research 提交 `7693c8b`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round63-base-city-assault-cap-post`。实际攻城行动数量、生产队列、伤亡和回合性能仍需原生 A/B 验证。

## Round 64：战时攻城定义门槛

- 依据 RHAI `Ops2.sql`，将原生 `Wartime Attack Enemy City` 设置为成功率门槛 0.2、至少 4 个单位，将 `Wartime Attack Walled City` 设置为 0.2、至少 5 个单位。
- 保留 R57/R58 编组门槛、R59 强度门槛、R63 基础攻城上限和原生战争条件；单位仍由正常生产和补兵形成。
- 不新增行动、不自动宣战、不直接生成单位、不改变单位成本。

Round 64 pre backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round64-wartime-city-attack-definitions-pre`；Endgame 提交 `9db1356`，Research 提交 `eb2853c`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round64-wartime-city-attack-definitions-post`。实际攻城频率、生产队列、伤亡和回合性能仍需原生 A/B 验证。

## Round 65：沿海城市防御编制

- 依据 RHAI `Ops4.sql`，将原生 `City Naval Defense` 队伍初始门槛设为 `-7`，舰船要求 2–8（比例 0.6–1），战斗单位 2–10，近战护航 0–3（比例上限 0.5）。
- 该队伍复用原生沿海 `City Defense` 行动，使受威胁沿海城市通过正常生产形成舰船与护航；不新增行动、不自动宣战、不直接生成单位、不改变单位成本。
- 只使用本机原生 `UNITTYPE_NAVAL`、`UNITTYPE_MELEE`、`UNITAI_COMBAT` 类型。

Round 65 pre backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round65-coastal-defense-team-requirements-pre`；Endgame 提交 `94ba562`，Research 提交 `1ab28e6`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round65-coastal-defense-team-requirements-post`。实际沿海防御触发、舰船队列、损耗和回合性能仍需原生 A/B 验证。
## Round 66：战前/战时单位储金与军事大将偏好

- `Data/EC_AIMilitaryDoctrine.sql` 接入 RHAI 使用的原生 `SavingTypes` 列表：战时 `SAVING_UNITS=8`，战前强势策略 `SAVING_UNITS=6`，受威胁城市 `SAVING_UNITS=8`。
- 战时 `STRATEGY_AT_WAR` 追加原生 `PSEUDOYIELD_GPP_GENERAL=50`，帮助 AI 通过军营/大将相关决策维持军力支持。
- 只使用 Steam 原生 `SAVING_UNITS`、`PSEUDOYIELD_GPP_GENERAL` 和已有策略条件；不复制 RHAI 自定义收益、不直接生成单位、不改变单位成本或人类玩家规则。

R66 依据证据：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-wartime-savings-generals-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round66-wartime-savings-and-generals-pre`；Endgame 提交 `1ca22e6b9182f9b50d3814fab61fdca2a00a09f0`，Research 提交 `25b2884c2ce121f5ebc226c31a4edbe4f4486a28`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round66-wartime-savings-and-generals-post`。离线合同已通过；实际金币购买、军队规模、军事大将获取和战争结束退出仍需原生 A/B 验证。
## Round 67：受攻击时立即花费储金补兵

- 依据 RHAI `STRATEGY_UNDER_ATTACK_SAVINGS`，将 `EC_AI_MILITARY_UNDER_ATTACK_SAVINGS/SAVING_UNITS` 从 R66 的实验值 `8` 修正为 `-2`；受攻击时减少储金倾向，让金币更快进入单位购买/补充。
- 依据同一 RHAI 列表，新增 `EC_AI_MILITARY_UNDER_ATTACK_PSEUDOS/PSEUDOYIELD_GPP_GENERAL=80`，加强紧急军事大将支持偏好。
- 只使用 Steam 原生类型，不直接生成单位、不改变单位成本或人类玩家规则。

R67 证据：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-under-attack-spending-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round67-under-attack-spending-pre`；Endgame 提交 `486ba8d`，Research 提交 `42b5ba5`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round67-under-attack-spending-post`。SQL/schema 验证通过；真实金币购买、单位增量、大将获取和战争结束退出仍需原生 A/B 验证。
## Round 68：战前强势 AI 的攻城与轰炸机优先级

- 依据 RHAI `Military_Strat.xml` 的 `STRENGTH_ADV_UNIT_BUILDS`，将 `EC_AI_MILITARY_STRENGTH_UNIT_BUILDS/PROMOTION_CLASS_SIEGE` 设为 11。
- 将同一列表的 `PROMOTION_CLASS_AIR_BOMBER` 设为 45 并标记 `Favored=1`；该列表仍只由已有 `STRATEGY_STRENGTH_ADV` 条件触发。
- 不新增策略条件、外交动作、战争行动或单位生成；其他单位组合值保持不变。

R68 证据：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-strength-siege-air-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round68-strength-siege-air-pre`；Endgame 提交 `91f6e89`，Research 提交 `0957621`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round68-strength-siege-air-post`。离线 schema 合同通过；实际时代可用性、队列比例、资源压力和回合性能仍需原生 A/B 验证。

## Round 69：战前强势 AI 的海空军伪收益

- RHAI 固定快照 `Military_Strat.xml` 的 `STRENGTH_ADV_PSEUDOS` 使用 `PSEUDOYIELD_UNIT_NAVAL_COMBAT=30` 与 `PSEUDOYIELD_UNIT_AIR_COMBAT=20`。
- Endgame 已将这两个值接到现有 `EC_AI_MILITARY_STRENGTH_PSEUDOS`；仍由已有 `STRATEGY_STRENGTH_ADV` 的军力/科技/分数条件门控。
- 该层只提高强势战前 AI 对海军和空军的原生评价，可能影响舰船、机场和轰炸机队列竞争；不直接生成单位、不修改单位成本、不新增外交或行动上限。
- Steam 原版 `Yields.xml`/Gameplay schema 已确认两个伪收益类型；Research 验证器已锁定 30/20，focused doctrine 与 Endgame SQL/XML 校验通过。

R69 证据文件：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-strength-air-naval-pseudos-audit-20261005.md`。R69 pre backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round69-strength-air-naval-pseudos-pre`；Endgame 提交 `c9d1ec0`，Research 提交 `41e9952`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round69-strength-air-naval-pseudos-post`。实际海空军生产队列、资源约束、时代可用性、战争前后差异和回合性能仍需原生 A/B 验证。

## Round 70：晚期极强 AI 的军事组合策略

- RHAI `Military_Strat.xml` 的 `STRATEGY_VERY_HIGH_STRENGTH_ADV_LATE` 使用晚期强势门控，并提高陆军、海军、空军、攻城和轰炸机组合偏好。
- 本机 Steam `Victories.xml` 只确认 `Leads Military`、`Has Tech Lead`、`Leads Score`、`Next Lower Score`、`Has Taken Capital`、`Is Industrial`、`Is Modern`、`Tourists Taken` 和 `Is Not Major`；RHAI 的 `Is Atomic`、`Is Infomation` 未在本机原版出现，因此没有移植。
- Endgame 新增 `STRATEGY_EC_MILITARY_VERY_HIGH_LATE`，要求上述原生条件至少四项成立，只接入 `PseudoYields` 与 `UnitPromotionClasses` 两个列表。伪收益为陆军 20、海军 25、空军 15、常备军数量 12、常备军价值 5；攻城 3、轰炸机 10。
- 该层只影响晚期明显强势主要 AI 的单位组合评价，不增加生产 modifier、外交动作、行动上限、核行动、单位生成或单位成本。

R70 证据文件：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-very-high-late-military-audit-20261005.md`。R70 pre backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round70-very-high-late-military-pre`；Endgame 提交 `19deba3`，Research 提交 `e54215e`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round70-very-high-late-military-post`。实际策略刷新、资源约束、生产队列和回合性能仍需原生 A/B 验证。

## Round 71：AI 军事生产叠加上限审计

- 新增 `tests/validate-ai-production-stack.py`，读取 Endgame 的 `EC_AIMilitaryProduction.xml`、`EC_AIMilitaryDoctrine.sql` 和五档 `GameSpeeds` SQL，核对每个生产 modifier、civic/资源层与速度层金额。
- 在“AI 开关已启用、5 城、晚期、军事工程、全部军事 civic、战略资源、高难度、对应速度”这一静态上界假设下，理论生产叠加为：战前晚期 `+94`、战时中期 `+134`、战时晚期 `+139`。
- 这是金额和条件的上限审计，不把所有 requirement 同回合成立或实际生产增量当作已证明；实际绑定时点、速度 criteria、战争/科技/civic 评估和回合性能仍需原生 A/B。
- 本轮没有增加运行时 modifier，避免在尚未有原生队列证据时继续扩大生产倍率。

R71 pre backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round71-ai-production-stack-audit-pre`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round71-ai-production-stack-audit-post`。当前审计结果：`AI production stack audit: PASS (civic_sum=28, resource_sum=6, speed_max=15, prewar_late=94, wartime_midgame=134, wartime_late=139)`。

## Round 72：升级与维护经济兼容性审计

- 对照 Late Game AI 8.29 的 `Combat.sql`，确认 GrandCampaign 使用原生单位维护费/升级折扣 modifier，但没有直接复制其动态难度金额或 Professional Army 所有者改写。
- Research 新增 `validate-ai-sustainment-stack.py`，检查 7 个升级/维护 modifier 的原生类型、AI/战争/科技/资源/难度门控、主要文明 trait 挂接、`Upgrade Units` 城市事件路径，以及 `PROFESSIONAL_ARMY_UNITUPGRADEDISCOUNT` 未被 doctrine 改写。
- 审计上限为和平升级 `+10%`、战时升级 `+20%`；维护费和平 `+4`、战时 `+5`。这些是静态金额上限，不代表原生回合实际折扣或免费升级。

R72 pre backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round72-ai-sustainment-audit-pre`；Research 提交 `4f692c346ddcfd28e2affb904be7680028868373`；Endgame 文档提交 `6211e89f5349047c2124cb349923dc128302a8d2`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round72-ai-sustainment-audit-post`。本轮尚未修改运行时 SQL/XML；原生升级队列、金币/维护费实际变化、政策叠加和回合性能仍需 A/B。

## Round 73：晚期极强 AI 生产偏好

- `Data/EC_AIMilitaryDoctrine.sql` 新增 `EC_AI_MILITARY_VERY_HIGH_LATE_YIELDS`，使用原生 `Yields/YIELD_PRODUCTION=12`。
- 该列表只由 `STRATEGY_EC_MILITARY_VERY_HIGH_LATE` 使用，要求已有至少四项晚期强势条件；保持已有单位组合权重，不新增生产 modifier、行动或单位生成。
- RHAI 自定义 `YIELD_RH_MILITARY_PRODUCTION` 未复制，因为本机 Steam 原版不存在该收益类型。

R73 pre backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round73-very-high-late-production-pre`；Endgame 提交 `b822cc7d51e997edd18ba9e1c7950114fa118c5b`；Research 提交 `c1855b622c3c43916d4773286de4ce0c280ab33c`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round73-very-high-late-production-post`。原生队列、策略刷新、资源约束和回合性能仍需 A/B。

## Round 74：战前强势 AI 生产偏好加固

- `EC_AI_MILITARY_STRENGTH_YIELDS/YIELD_PRODUCTION` 由 18 调整为 24，仍只在 `STRATEGY_STRENGTH_ADV` 已有强势条件下生效。
- 该层是 AI 决策权重，不是城市生产 modifier；受攻击层 30 和战时层 25 保持不变。
- 不复制 RHAI 自定义收益，不增加行动、外交或单位生成。

R74 pre backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round74-strength-prewar-production-pre`；Endgame 提交 `3d55878093bec9e73fde19632a0fdf40a83a0695`；Research 提交 `36d001adb2754f2730dac36c5d98e7a106fb2dda`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round74-strength-prewar-production-post`。原生战前队列、资源压力和回合性能仍需 A/B。


## Round 75：升级资源消耗效果兼容性审计

- RHAI/GoldenAge 的升级资源折扣效果在本机 Steam 原版没有可验证的 DynamicModifier 映射，因此本轮不新增运行时 SQL/XML。
- Research 侧新增 fail-closed 兼容性验证，继续保留 AI-only 金币升级折扣和既有 Upgrade Units 事件路径。
- 原生升级资源消耗、金币消耗、队列刷新和回合性能仍需独立测试模组或同存档 A/B。

## Round 76：高难度 AI 军用生产加固

- `EC_AI_MILITARY_HIGH_DIFFICULTY` 使用原生 `PLAYER_IS_HIGH_DIFFICULTY_AI` owner requirement，Amount 从 `5` 调整为 `10`。
- 这是 AI-only 军用单位生产层，不改变普通难度、全城生产 modifier、速度层或人类玩家规则。
- 生产叠加静态审计更新为战前晚期 `+99`、战时中期 `+139`、战时晚期 `+144`；实际游戏效果仍需原生回合验证。

R76 编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round76-high-difficulty-military-production-pre`；Endgame 提交 `6552511`；Research 提交 `9321a8b`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round76-high-difficulty-military-production-post`。

## R78 变更与下一步

- 完整 Steam 安装中的 Expansion1/2 原生数据现在由验证器锁定：全单位购买成本 effect 合同存在；Endgame 接入 AI-only、默认关闭、战前 +10/战时 +20、`IncludeCivilian=0` 的购买折扣。
- R78 pre backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round78-unit-purchase-discount-pre`。仍需原生 A/B 记录金币储备、购买次数、单位总数、战争结束后的恢复与回合耗时，再决定是否调整 10/20。

## R79 变更与下一步

- 依据 RHAI `AggressiveYields/YIELD_GOLD=10` 和本机原生 `Yields.xml`，强势战前/战时/受攻击策略增加 `YIELD_GOLD=6/8/10`；R78 购买折扣和 R77 储金方向保持。
- R79 pre backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round79-military-gold-preference-pre`。仍需原生 A/B 记录金币净变化、单位购买次数、单位总数、生产队列和回合耗时。

## R80 变更与下一步

- Gathering Storm `Expansion2_Modifiers.xml` 已确认原生战略资源升级折扣映射；Endgame 接入 AI-only `Amount=20` 基础层与已知战争 `Amount=20` 增量层，理论上限 `20%/40%`。
- 既有金币升级折扣、单位购买折扣、金币偏好和 `SAVING_UNITS` 方向保持；不直接生成单位、不改人类规则、不改 `PROFESSIONAL_ARMY` 所有权。
- R80 pre backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round80-strategic-resource-upgrade-discount-pre`；提交 `48606e4`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round80-strategic-resource-upgrade-discount-post`。仍需原生 A/B 记录战略资源扣除、升级次数、单位总数、战争退出恢复和回合耗时。

## R81 变更与下一步

- 依据 GoldenAge 的资源积累实现和 Gathering Storm `Expansion2_Modifiers.xml` 原生映射，加入铁、马、硝石、煤、石油、铝、铀 7 种战略资源的 AI-only 积累层：和平每种 `+1`，已知战争再 `+1`。
- 所有 14 条 modifier 均挂到 `TRAIT_LEADER_MAJOR_CIV`，使用 `PLAYER_IS_AI` 或 `EC_AI_MILITARY_WARTIME_OWNER`；不改变人类玩家，也不直接生成单位。
- R81 pre backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round81-strategic-resource-accumulation-pre`；提交 `65eb029`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round81-strategic-resource-accumulation-post`。仍需原生 A/B 记录资源净积累、生产/升级次数、单位数量、战争退出恢复和回合耗时。

## Round 82：战略资源落点评价

- 依据本机 Steam `Agendas.xml` 的 `StandardSettlePlot -> PlotEvaluations` 原生合同，以及 Real Strategy/RHAI 的战略资源落点评价，新增 `EC_AI_MILITARY_RESOURCE_SETTLEMENT`。
- 该列表在 `STRATEGY_STRENGTH_ADV`、`STRATEGY_AT_WAR` 和 `STRATEGY_EC_MILITARY_BEHIND` 激活时，提高战略资源类别及铁、马、硝石、煤、石油、铝、铀的落点评价；权重为 `4`、`3/4/4/4/5/6/8`。
- 这一层让 AI 在战前扩张、军力落后恢复和战争期间更重视正常可占领的战略资源地块，配合 R80 升级资源折扣与 R81 资源积累；不直接生成单位、不改变人类玩家、不改资源分布或单位成本。

R82 证据：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-strategic-resource-settlement-r82-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round82-strategic-resource-settlement-pre`。原生落点选择、资源占有、生产/升级队列、单位数量和回合性能仍需同存档 A/B。

## Round 83：城市级战略资源积累

- 依据 Gathering Storm `Expansion2_Modifiers.xml` 的原生 `MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE` 映射，以及 RHAI 的 `AI_BONUS_STRATEGICS_*` 城市资源层，新增 14 条 AI-only 城市级战略资源积累 modifier。
- 和平层对每个 AI 城市增加铁、马、硝石、煤、石油、铝、铀各 `+1`；已知战争再增加同样的每城 `+1`，静态上限为每城 `7/14`。
- 这一层与 R81 的玩家全局 `7/14` 积累分开审计，为训练、购买和升级提供更直接的城市资源供给；不直接生成单位、不改变人类玩家、不改资源分布或单位成本。

R83 证据：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-city-resource-accumulation-r83-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round83-city-resource-accumulation-pre`。原生资源库存、资源上限、生产/升级队列、单位数量和回合性能仍需同存档 A/B。

## Round 84：科技门控城市战略资源积累

- 依据 RHAI `AI_BONUS_STRATEGICS_*_2` 和本机原生科技要求，新增 7 条城市级科技门控资源积累 modifier。
- 军事工程解锁马/铁各 `+1`；工业化解锁硝石 `+2`；化学解锁煤/石油/铝各 `+1`；核聚变解锁铀 `+2`。每项均为 AI-only，静态额外上限为每城 `9`。
- 该层叠加 R83 的基础/战时城市资源供给，随科技现代化推进，提高战前整备和战时补兵资源吞吐；不直接生成单位、不绕过科技、不改变人类玩家或单位成本。

R84 证据：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-tech-city-resource-accumulation-r84-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round84-tech-city-resource-pre`。原生科技刷新、资源库存、生产/升级队列、单位数量和回合性能仍需同存档 A/B。

## Round 85：RHAI 晚期科技城市资源积累

- 依据 RHAI `AI_BONUS_STRATEGICS_*_3` 和本机原生科技要求，新增六条 AI-only 城市资源 modifier：工业化后马 `+2`、铁 `+1`；化学后硝石 `+2`；联合武器后煤/石油 `+2/+2`、铝 `+1`。
- 所有 modifier 使用原生 `MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE`，挂到 `TRAIT_LEADER_MAJOR_CIV`，晚期层每城静态额外上限为 `10`。
- 该层补强战前整备与战时补兵所需的现代战略资源吞吐，配合 R80–R84 的升级折扣、全局积累、落点评价和城市科技层；不直接刷兵、不绕过科技、不影响人类玩家。

R85 证据：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-late-tech-city-resource-accumulation-r85-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round85-late-tech-city-resource-pre`；原生库存、队列、单位数量和回合性能仍需同存档 A/B。

## Round 86：城市战略资源需求折扣

- 依据 RHAI `AI_ARMY_STRATEGIC_RESOURCE_COST_DISCOUNT` 和本机原生 Expansion2 effect，新增 AI-only 城市资源需求折扣父子 modifier。
- 父级 `MODIFIER_PLAYER_CITIES_ATTACH_MODIFIER` 使用 `PLAYER_IS_AI`，子级 `MODIFIER_CITY_ADJUST_STRATEGIC_RESOURCE_REQUIREMENT_MODIFIER` 使用 `Amount=20`，父级挂到 `TRAIT_LEADER_MAJOR_CIV`，避免人类玩家继承。
- 该层作用于城市训练/购买所需的战略资源需求，与 R80 的升级资源折扣分开；保持单层有界值，不直接刷兵、不改变科技或人类规则。真实资源扣除、训练/购买次数、单位总量和性能仍需 A/B。

R86 证据：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-city-resource-requirement-discount-r86-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round86-city-resource-requirement-discount-pre`。

## R87 变更与下一步

Endgame R87 新增 AI-only `EC_AI_MILITARY_RESOURCE_STOCKPILE_CAP`，使用本机 Gathering Storm 原生 `MODIFIER_PLAYER_ADJUST_RESOURCE_STOCKPILE_CAP`，`PLAYER_IS_AI`、`Amount=10`，并挂到主要文明 trait。它为已有战略资源积累/需求折扣留出原生库存空间，服务训练、购买和升级的正常路径；不直接刷兵、不影响人类玩家、不改写 `Professional Army`，也不再复制一个战时副本。实际库存和爆兵增量仍需原生 A/B。post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round87-resource-stockpile-cap-post`。

## R88：AI 军营区域生产加速

R88 对照本机 Steam Base `Modifiers.xml` 的 `MODIFIER_PLAYER_CITIES_ADJUST_DISTRICT_PRODUCTION` / `MODIFIER_PLAYER_CITIES_ADJUST_BUILDING_PRODUCTION` 原生合同，并参考 GoldenAge 的区域筛选写法与 Late Game AI 的建筑生产 modifier，新增两个 AI-only modifier：`EC_AI_MILITARY_ENCAMPMENT_PRODUCTION` 和 `EC_AI_MILITARY_ENCAMPMENT_BUILDINGS_PRODUCTION`。两者均筛选 `DISTRICT_ENCAMPMENT`，`Amount=15`，挂到 `TRAIT_LEADER_MAJOR_CIV`，覆盖战前和战时的军营区域及其区域建筑建设，不复制额外战争层。

该层只提高军营建设速度，承接既有军用生产、资源供给和升级层；不直接生成单位、不改变人类规则、不提高全城或民用建筑生产。证据见 `C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-encampment-production-r88-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round88-encampment-production-pre`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round88-encampment-production-post`。静态合同已验证，原生生产队列、军营建造时点、单位数量和回合性能仍需 A/B。

## R89：晚期 AI 单位资金保留

R89 对照 RHAI `DefaultSavings/SAVING_UNITS=3` 与 `AggressiveSavings/STRATEGY_UNDER_ATTACK=-2` 的成熟方向，为现有 `STRATEGY_EC_MILITARY_LATE` 增加 `EC_AI_MILITARY_LATE_SAVINGS`，使用原生 `SavingTypes`、`SAVING_UNITS=3`。这让工业/现代时代 AI 在战前更明确地保留金币用于单位购买和补充，同时保持已有战时 `-2` 花费层不变。

该层只改变 AI 的金币分配偏好，不发放金币、不改变单位价格、不直接生成单位、不影响人类玩家。证据见 `C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-late-unit-funding-r89-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round89-late-unit-funding-pre`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round89-late-unit-funding-post`。原生晚期金币储备、购买次数、单位数量和回合性能仍需 A/B。

## R90：军力落后 AI 单位资金保留

R90 在已有 `STRATEGY_EC_MILITARY_BEHIND`（原生 `Lags Military`、阈值 33）上增加 `EC_AI_MILITARY_BEHIND_SAVINGS`，接入原生 `SavingTypes` 并使用 `SAVING_UNITS=3`。军力落后的主要 AI 在进入战时/受攻击紧急花费层前，会更明确地保留金币用于单位购买与补充；已有 `SAVING_UNITS=-2` 层仍负责紧急支出。

该层沿用 RHAI `DefaultSavings=3` 的已验证方向，只改变 AI 金币分配偏好，不发放金币、不改变单位价格、不直接生成单位、不影响人类玩家。证据见 `C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-military-behind-unit-funding-r90-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round90-military-behind-unit-funding-pre`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round90-military-behind-unit-funding-post`。军力落后触发率、金币余额、购买次数、单位数量和回合性能仍需 A/B。

## R91：军力落后 AI 金币偏好

R91 为 `STRATEGY_EC_MILITARY_BEHIND` 的 `EC_AI_MILITARY_BEHIND_YIELDS` 增加原生 `YIELD_GOLD=6`。它与 R90 的 `SAVING_UNITS=3` 形成军力恢复资金层：军力落后的主要 AI 更容易积累金币并保留资金，随后通过原生购买、升级和训练路径补充部队；战时 8、受攻击 10 以及紧急 `SAVING_UNITS=-2` 仍保持更高强度。

该层只调整 AI 收益权重，不发放金币、不改变单位价格、不直接生成单位、不影响人类玩家。证据见 `C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-military-behind-gold-preference-r91-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round91-military-behind-gold-preference-pre`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round91-military-behind-gold-preference-post`。实际金币净收入、购买次数、单位数量和回合性能仍需 A/B。

## R92：晚期 AI 金币偏好

R92 为 `STRATEGY_EC_MILITARY_LATE` 的 `EC_AI_MILITARY_LATE_YIELDS` 增加原生 `YIELD_GOLD=4`。工业/现代时代 AI 现在在晚期生产、兵种和 `SAVING_UNITS=3` 之外，拥有有限的现金流偏好，用于原生单位购买与升级；战时 8、受攻击 10 的更高金币层保持不变。

该层只调整 AI 收益权重，不发放金币、不改变单位价格、不直接生成单位、不影响人类玩家。证据见 `C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-late-gold-preference-r92-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round92-late-gold-preference-pre`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round92-late-gold-preference-post`。实际金币、购买/升级次数、单位数量和回合性能仍需 A/B。

## R93：受攻击 AI 空军拦截偏好

R93 对照 RHAI `core/Leaders/Trait_Leader.sql` 的 `DefensiveUnitBuilds`：`PROMOTION_CLASS_AIR_FIGHTER=5`，而 `AggressiveUnitBuilds` 对同类为空军负权重。GrandCampaign 在 `EC_AI_MILITARY_UNDER_ATTACK_UNIT_BUILDS` 增加原生 `PROMOTION_CLASS_AIR_FIGHTER=3`，并保持轰炸机 `2`，把该层限制在受攻击紧急防御策略。

该层只改变 AI 的原生兵种选择偏好，不直接创建单位、不影响和平或普通战时列表、不改变人类玩家规则。证据见 `C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-under-attack-air-fighter-preference-r93-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round93-under-attack-air-fighter-preference-pre`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round93-under-attack-air-fighter-preference-post`。受威胁城市的机场、铝供给、战斗机队列、空军数量和回合性能仍需原生 A/B。

## R94：晚期极强 AI 科技与市政路径

R94 对照 RHAI `AggressiveTechs`/`AggressiveCivics` 的原生 `Technologies`/`Civics` 列表系统，为已有四项强势信号门控的 `STRATEGY_EC_MILITARY_VERY_HIGH_LATE` 增加 `EC_AI_MILITARY_VERY_HIGH_LATE_TECHS` 与 `EC_AI_MILITARY_VERY_HIGH_LATE_CIVICS`。科技权重为 `6/7/8`，市政权重为 `5/6/7`，高于普通晚期层但仍有界。

该层只改变原生科技和市政选择偏好，不改变成本、不直接生成单位、不触发外交、不影响人类玩家；仍由统一 AI 开关默认关闭。证据见 `C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-very-high-late-tech-civics-r94-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round94-very-high-late-tech-civics-pre`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round94-very-high-late-tech-civics-post`。晚期科技/市政刷新、军用队列、资源、单位数量和回合性能仍需原生 A/B。

## R95：晚期极强 AI 军用基础设施偏好

R95 对照 RHAI `AggressiveSpecializations`/`AggressiveBuildings`/`AggressiveDistricts` 的原生列表系统，并复用已核对的军用建筑与区域类型，为 `STRATEGY_EC_MILITARY_VERY_HIGH_LATE` 增加 `AiBuildSpecializations`、`Buildings`、`Districts` 三个策略局部列表。专业化为 `BUILD_MILITARY_UNITS=5`、`BUILD_CITY_DEFENSES=4`；军用建筑为兵营、马厩、军械库、军事学院各 `3`；军营/机场区域为 `5/3`。

该层只改变原生城市建造偏好，不直接生成单位、不改变成本、不影响人类玩家；仍由四项强势条件和统一 AI 开关限制。证据见 `C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-very-high-late-infrastructure-r95-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round95-very-high-late-infrastructure-pre`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round95-very-high-late-infrastructure-post`。军用基础设施队列、单位数量、战略资源和回合性能仍需原生 A/B。

## R96：晚期极强 AI 行动与城市升级事件

R96 对照 RHAI `AggressiveOperations` 的原生 `AiOperationTypes` 模式，并复用已通过验证的 `PerWarOperationTypes` 与 `CityEvents` 合同，为 `STRATEGY_EC_MILITARY_VERY_HIGH_LATE` 增加 `CITY_ASSAULT=2`、`OP_DEFENSE=2`，每场战争行动各 `1`，以及默认/受威胁城市均选择 `Upgrade Units`。

该层只改变晚期极强 AI 的原生行动与城市升级偏好，不直接生成单位、不自动宣战、不改变单位成本、不影响人类玩家；仍由四项强势条件和统一 AI 开关限制。证据见 `C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-very-high-late-operations-r96-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round96-very-high-late-operations-pre`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round96-very-high-late-operations-post`。原生行动创建、队伍组建、升级队列、单位数量和回合性能仍需 A/B。
## R97：晚期极强 AI 单位资金支出偏好

R97 对照 RHAI `AggressiveSavings` 的原生 `SavingTypes/SAVING_UNITS=-2`，为已有四项强势信号门控的 `STRATEGY_EC_MILITARY_VERY_HIGH_LATE` 增加 `EC_AI_MILITARY_VERY_HIGH_LATE_SAVINGS`。普通晚期策略继续使用 `SAVING_UNITS=3`；达到晚期极强门槛的主要 AI 则更偏向立即把保留资金用于单位购买与补充。

该层只改变 AI 的原生花费方向，不发放金币、不直接生成单位、不改变单位成本、不自动宣战、不影响人类玩家。证据见 `C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-very-high-late-savings-r97-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round97-very-high-late-savings-pre`；post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round97-very-high-late-savings-post`。实际策略触发、金币余额、购买次数、单位数量和回合性能仍需原生 A/B。
## R98：晚期极强 AI 生产权重

R98 对照 RHAI `AggressiveYields` 的原生 `Yields/YIELD_PRODUCTION=25`，将 `STRATEGY_EC_MILITARY_VERY_HIGH_LATE` 的同名偏好从 `12` 提高到 `25`。该策略仍需要 `Leads Military`、`Has Tech Lead`、`Leads Score`、`Next Lower Score` 四项信号，并受工业/现代和主要文明条件限制；普通晚期策略的生产权重 `20` 保持不变。

该层只改变已占优晚期 AI 的原生生产选择权重，不直接刷兵、不发放生产、不改变成本、不自动宣战、不影响人类玩家。证据：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-very-high-late-production-r98-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round98-very-high-late-production-pre`；原生 A/B 仍需确认策略触发、队列、单位数、购买/升级、战争转换和回合性能。 post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round98-very-high-late-production-post`。

## R99：战时 AI 现金流偏好

R99 对照 RHAI `STRATEGY_AT_WAR_YIELDS` 的原生 `Yields/YIELD_GOLD=15`，将 GrandCampaign 的战时金币权重从 `8` 提高到 `15`。战时生产 `25`、`SAVING_UNITS=-2`、购买折扣、升级路径和资源/生产 modifier 保持不变；受攻击层 `YIELD_GOLD=10`、普通晚期层 `4` 也保持不变。

该层只改变已经处于战争状态的 AI 收益选择，不直接发金币、不刷单位、不改单位价格、不自动宣战、不影响人类玩家。证据：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-wartime-gold-preference-r99-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round99-wartime-gold-pre`；原生 A/B 仍需确认金币、购买/升级、生产队列、单位数、战争退出和回合性能。 post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round99-wartime-gold-post`。

## R100：晚期极强 AI 现金流偏好

R100 对照 RHAI `AggressiveYields` 的原生 `YIELD_PRODUCTION=25` 与 `YIELD_GOLD=10`，为 `STRATEGY_EC_MILITARY_VERY_HIGH_LATE` 增加 `YIELD_GOLD=10`。R98 的生产 `25`、R97 的 `SAVING_UNITS=-2`、R99 的战时金币 `15`、普通晚期金币 `4` 和受攻击金币 `10` 保持分层不变。

该层只改变已占优晚期 AI 的原生现金流选择，不直接发金币、不刷单位、不改单位价格、不自动宣战、不影响人类玩家。证据：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-very-high-late-gold-preference-r100-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round100-very-high-late-gold-pre`；原生 A/B 仍需确认金币、购买/升级、生产队列、单位数和回合性能。 post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round100-very-high-late-gold-post`。

## R101：晚期极强 AI 常备军规模偏好

R101 对照 RHAI `AggressivePseudoYields` 的原生 `PSEUDOYIELD_STANDING_ARMY_NUMBER=27` 与 `PSEUDOYIELD_STANDING_ARMY_VALUE=16`，将 `STRATEGY_EC_MILITARY_VERY_HIGH_LATE` 原有的 `12/5` 提高到 `27/16`。R98 的生产 `25`、R100 的金币 `10`、R97 的 `SAVING_UNITS=-2` 以及其他阶段层保持不变。

该层只改变已占优晚期 AI 对常备军规模和价值的原生偏好，不直接刷兵、不发放生产或金币、不改单位价格、不自动宣战、不影响人类玩家。证据：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-very-high-late-army-pseudos-r101-audit-20261005.md`。编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round101-very-high-late-army-pseudos-pre`；原生 A/B 仍需确认单位数量、队列、资源压力和回合性能。 post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round101-very-high-late-army-pseudos-post`。

## R102：晚期极强 AI 海空军伪收益

R102 对照 RHAI `AggressivePseudoYields` 的原生 `PSEUDOYIELD_UNIT_NAVAL_COMBAT=65` 与 `PSEUDOYIELD_UNIT_AIR_COMBAT=40`，将 `STRATEGY_EC_MILITARY_VERY_HIGH_LATE` 原有的 `25/15` 提高到 `65/40`。R101 的常备军数量/价值 `27/16`、R98 的生产 `25`、R100 的金币 `10`、R97 的 `SAVING_UNITS=-2` 和其他阶段层保持不变。

该层只改变已占优晚期 AI 对海军和空军单位的原生评价权重，不直接刷兵、不发放生产或金币、不改单位价格、不自动宣战、不影响人类玩家。证据：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_References\20261004-ai-war\workshop\2939752243-RHAI-very-high-late-air-naval-pseudos-r102-audit-20261005.md`；编辑前备份：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round102-very-high-late-air-naval-pseudos-pre`；原生 A/B 仍需确认港口/机场条件、资源压力、队列比例、单位数量和回合性能。


R102 post backup：C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round102-very-high-late-air-naval-pseudos-post。

## R103：AI 军事绑定器性能与错误循环保护

R103 针对 AI 军事生产 Lua 绑定器的每回合开销和失败循环：20 个 native modifier 全部成功后写入 `EC_AI_MILITARY_PRODUCTION_COMPLETE=APPLIED`，后续回合直接跳过该 AI 的 modifier 状态扫描；热重载通过持久完成标记同样跳过。

属性读写失败会在当前 Lua 会话把玩家放入阻断集合，避免状态写入不可用时每回合重复尝试；原生 modifier 返回 `false` 的既有三次重试和 `UNKNOWN` 终止规则保持不变。该层不改变 modifier 数值、不直接刷兵、不影响人类玩家。

验证：AI 军事生产回归扩展为 `7/7`，覆盖完成标记、热重载短路和状态写入失败阻断；完整回归和静态合同仍需本轮最终复跑。


R103 post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round103-ai-production-completion-guard-post`。



## R104：AI 决策性能与循环合同审计

R104 新增 Research 验证器 `tests/validate-ai-decision-performance.py`，并提供 `npm run validate:ai-performance`。它检查 AI 军事绑定器的 20 个 modifier 清单、唯一 ID/键、最大三次 native 重试、同回合短路、完成/阻断状态、64 个主要 AI roster 上限和无界 `while/repeat/goto`；同时检查 doctrine 的策略优先级无重复、每个策略局部列表不超过 16 个、条件阈值不超过条件数。

当前结果：`modifiers=20`、`max_attach_attempts=3`、`strategy_priority_rows=76`、最大策略列表 `14`、有条件策略 `5` 组、无界循环 `0`。这是静态性能/循环合同，不代替原生 AI 回合耗时剖析。
R104 post backup：C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261005-round104-ai-decision-performance-audit-post。


## R105：AI 绑定器 schema 读取缓存

R105 将 AI 军事绑定器的 `SCHEMA` 属性读取移到每个未完成玩家的一次性上下文中，20 个 modifier 不再重复读取同一属性；首次成功写入 schema 后在上下文中更新缓存。离线夹具中的完整绑定路径从 61 次属性读取降为 42 次，且完成标记路径仍不读取 modifier 状态。

无效 schema 现在会立即标记为 UNKNOWN 并阻断当前会话玩家，避免每回合重复扫描 20 个 modifier；原生 modifier 值、玩家筛选、三次重试和默认关闭条件均未改变。

## Round 108：MCP 总览边界与 AI 实机证据状态

MCP `0dfaa9f` 已将总览中的可选玩家评分、外交和 favor 原生成员读取改为 fail-closed，并以 110 项 pytest、编译检查和 MCP 实机连接探针验证。当前 Steam Civ6 停在中文主菜单，FireTuner 仅发现连接而无 `GameCore`/`InGame` 状态；AI 状态探针读到测试配置和存活主要文明，但 `EC_AI_` modifier 数量为 0 只说明当前未载入可观测模组状态，不能据此判定 Endgame 数据未加载。

本轮未改变 Endgame AI 数值或 Lua 绑定器；静态 doctrine/production 合同继续通过。真实战前/战时 AI A/B 仍未完成，需在载入带已接触文明或战争状态的 Endgame 存档后记录生产队列、单位/城市、金币/战略资源、战争转换和回合耗时。

## Round 109：Endgame 原生 MCP 实机回合核验

本轮没有改变 Endgame AI 数值或绑定器。通过 Civ6 中文菜单加载 `0_MCP_0029`，从罗马领导者介绍页进入世界后，常驻 MCP 的 `POST /api/test/advance` 成功将 T29 推进到 T30，并返回原生胜利快照、野蛮人骑射手威胁和闲置贸易路线事件。T30 读取为罗马/图拉真、1 城、5 个勇士、人口 3、金币 230、科学 3.5、文化 3.9、信仰 17、分数 26。

`/api/test/ai-mod-status` 记录 `modifier_count=0`、`config_test=nil` 和两个存活主要文明行；该值只说明当前实机查询结果，不能证明 Endgame modifier 未加载。完整说明见 `docs/28-native-mcp-runtime-turn30-20261006.md`，Round 109 运行时快照和 Git bundle 位于 `C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261006-round109-runtime-pre`。当前存档仍没有已接触文明或战争状态，真实 AI 军事 A/B 仍待带条件存档验证。

随后 MCP 提交 `3179163` 为同一探针增加了 fail-closed 的 `active_mods` 字段；缺少 `Modding.GetActiveMods()` 时返回空数组，不影响现有总览或回合推进。该提交的 111 项 MCP 回归、compileall 和差异检查通过；当前常驻进程会在下一次 MCP 重启后加载该字段。

## Round 110：MCP AI 观测与实机验证入口

本轮 MCP 提交 374f198、c716dc2、483968e 增加只读 AI 观测、回合耗时、受保护的 modifier/active-mod 探针，并把旧的 0_MCP_*.Civ6Save 归档到 _abandoned_mcp，避免自动启动清理重要存档。MCP 回归 116 passed，compileall 和差异检查通过。主菜单态的 AI 接口稳定返回 HTTP 503，表示无 GameCore/InGame，不能据此判断 Endgame 是否启用。下一步只需在加载 Endgame 存档后收集城市队列、单位、资源、战争转换和耗时，做同存档 A/B。

详见 docs/29-mcp-ai-observation-autoboot-20261006.md。Round 110 MCP 备份：C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261006-round110-mcp-ai-observation-post。

## Round 111：MCP 原生菜单加载检测

MCP 已增加本地原生存档检测接口，并在所有前端 Lua 状态上查询存档列表，再优先选择 `LoadGameMenu` 状态发送 `Network.LoadGame`。实机查询已确认 `GC_RUNTIME_T30_ENDGAME_AUDIT.Civ6Save` 可被 FireTuner 原生列表回调看到；两次加载请求触发了重载断连，但尚未确认重载后 `GameCore`/`InGame` 恢复，因此不能把这次结果当作 Endgame AI 实机证据。Endgame AI 数值和 SQL/XML 未改变；下一步仍是恢复同存档运行态后采集 modifier/config、城市队列、单位、资源、战争和回合耗时。

## Round 112：MCP 实机加载判定（2026-10-07）

MCP 已把 FireTuner 的 `Network.LoadGame=true` 与真实加载状态分开：只有重新发现 `GameCore_Tuner` 和 `InGame` 才算成功。控制存档已通过 MCP OCR 回退加载并被 `/api/overview`、`/api/test/ai-observation` 读取；控制存档的 GrandCampaign modifier 为 0，因此不能作为 Endgame 效果证据。Endgame 目标存档的原生文件查询和 22 个 RequiredMods 检查通过，但原生调用仍返回前端，OCR 未能在本地化列表中稳定找到目标名。本轮未修改 Endgame SQL/XML/AI 数值，也未删除目标存档。

下一步：用 native `g_FileList` 索引或兼容性弹窗完成目标存档重载；恢复 GameCore/InGame 后记录晚期 AI 的 modifier/config、队列、单位、收益、战争和回合耗时。MCP 证据见 `C:\Users\Administrator\Desktop\mIDDLEFILE\civ6-mcp-main\docs\31-runtime-load-verification-20261007.md`。

## Round 113：MCP active-mod 运行时边界（2026-10-07）

MCP 静态回归和本项目离线合同均通过：Research 的 12 个 validate-*.py 加 3 个 PowerShell 校验、workspace/PowerShell、Endgame/Stability SQL/XML 校验全部 PASS。MCP 新增只读 active-mod 探针后，全量回归为 121 passed，compileall 和差异检查通过。

实际读取 GC_RUNTIME_T30_ENDGAME_AUDIT 已恢复 GameCore=3、InGame=119，并读到 T31 的两个主要文明 diary。Main State 的 Modding.GetActiveMods 只返回 23 个官方内容项；Endgame ID 2af0c438-bab0-4d0c-987f-0beaf0f7c7f2、Stability ID 7b9b91d9-6ce7-4fc7-93c2-1c170ccbf401 和 TestFlow ID b7f8e82d-2ef8-4db3-a1a7-91ac8c5d7f13 均不在 active 集合，EC_AI_MILITARY_PRODUCTION_TEST=nil。该存档因此只能作为 MCP 读档/观测链路证据，不能作为 Endgame 效果 A/B。

本轮未修改 Endgame 的 SQL/XML/Lua 数值。下一步先在目标模组实际 active 的新存档中重新做 AI modifier/config、队列、单位、资源、战争和回合耗时采集；目标存档与可逆副本继续保留。

## Round 114：静态构建优先（2026-10-07）

用户确认本机 Endgame 模组已启用；本轮停止游戏检验，全部工作转为静态构建。此前 active-mod API 未返回本地 ID 的结果只保留为诊断证据，不改变模组已启用的项目判断。

Endgame 的 SQL/XML、AI doctrine、生产/维护/升级合同、modinfo 和组合配置继续以离线校验为准。后续先完善源码和验证器，暂不新增原生 A/B 结论。

## Round 115：UI 表面审计（2026-10-07）

静态审计确认四个 InGame UI action 均有 XML/Lua companion、manifest 条目、Context 和确定的 LoadOrder：左上角 `LaunchBar/ButtonStack` 入口（30000）、只读附庸总览面板（30001）、受 `EC_PLAYER_CONSENT_TEST` 门控的确认弹窗（29999）和隐藏指标桥（29998）。新增 Research `tests/validate-ui-contract.py`，检查关键控件/回调、就绪重试、PopupDialog/RequestPlayerOperation 桥和屏幕注入 API 禁止项。

当前总览仍是只读 UI；真实附庸/复国没有提交按钮，也没有绑定原生城市、单位和玩家 adapter。`EC_VassalTransaction.lua` 仍是离线事务计划库，不能把 UI 静态通过解释为真实附庸已生效。详见 Research `docs/34-ui-surface-audit-20261007.md`；本轮不启动游戏或使用 Computer Use。

## Round 116：候选资格与事务门禁视图（2026-10-07）

总览模型现在只读解析 `EC_ADVANTAGE_` 双缓冲资格记录，并把有效候选、失效候选和损坏记录分别显示在附庸面板；面板新增事务状态行，明确真实附庸/复国 adapter 尚未接通。该层不发起 `RequestPlayerOperation`，不写 Property，也不调用城市、单位或玩家变更 API。

总览 UI 回归扩展为 `45/45`，新增资格记录、损坏 bank 和事务状态文案覆盖；本轮仍未把候选观察当作真实附庸资格或执行证据。

## Round 117：事务能力证据入口（2026-10-07）

MCP 新增只读 `GET /api/test/endgame-capabilities`，为后续原生检验清点城市转移、单位清理、玩家集合和属性 API 的成员存在性。它不调用变更方法；在经过审查的原生 adapter 显式接入前，`adapter_ready` 固定为 false。附庸面板继续保持候选展示和事务待接通状态，不增加提交按钮。

## Round 118：标准附庸 API 边界（2026-10-07）

能力探针现在还单独检查 `CityCommandTypes.TRANSFER_CITY`、`CityCommandTypes.CHANGE_OWNER`、`PlayerOperations.VASSALIZE` 和 `PlayerOperations.RESTORE_CIVILIZATION`。普通 `RequestCommand` 或外交操作不会被当作城市转移能力；在这些符号和参数语义未得到原生证据前，事务 UI 继续关闭。

## Round 119：事务模块静态契约（2026-10-07）

Research 新增静态验证器，锁定 `EC_VassalTransaction` 的六个写入 adapter 方法、四个验证读取方法和 journal fail-closed 边界，并确认事务模块没有直接访问未经确认的 Civ6 原生对象。旧日志中的 `TransferCity` 已明确标为候选签名；当前实现继续只生成计划并保持 UI 操作门关闭。

## Round 120：项目文档结构契约（2026-10-07）

Research 聚合入口新增 `validate-project-docs.py`，检查四个 PROJECT.md 的恢复字段和 TestFlow 的静态-only 约束，纳入 `validate-all-static.ps1` 的 `validate-*.py` 扫描。它只保证项目状态可恢复，不扩大原生 API 或游戏运行时结论。

## Round 121：PROJECT schema 校验器（2026-10-07）

Research 新增 `tools/validate_project.py`、`schema/project.schema.json` 和聚合兼容入口，PROJECT.md 的目标/要求/决策/进度/下一步/未解决问题字段现在按 schema 结构检查；本轮不改变任何游戏运行时结论。

## Round 122：离线回归基线同步（2026-10-07）

根据最新聚合输出，当前完整 Lua 离线套件为 `497/497`；总览 UI 为 `45/45`，附庸事务为 `29/29`。历史轮次数字保留在原记录中，不把静态回归结果解释为原生游戏渲染或事务生效证据。

## Round 123：静态优先边界强制（2026-10-07）

PROJECT schema 校验器现在要求每个项目文档显式记录 static-first 边界；聚合验证继续覆盖 UI、事务、SQL/XML、Lua、TestFlow 和 MCP 文档。该轮不启动游戏、不新增原生运行时结论。

## Round 124：Endgame UI 几何布局合同（2026-10-07）

Research 新增 `tests/validate-ui-layout.py`，静态检查左上角按钮/图标、总览面板、滚动区和档案行的固定尺寸、锚点与重复 ID；本轮不启动游戏，不把几何合同当作原生渲染证据。

## Round 125：事务状态 footer 防遮挡（2026-10-07）

总览面板现在读取 `OperationStatus` 和只读提示的实际控件高度，动态预留底部空间，长本地化状态不会侵入档案滚动区；Research 总览回归为 `46/46`。本轮不启动游戏。

## Round 126：MCP 纳入统一静态门槛（2026-10-07）

Research 聚合静态入口现在同时验证 MCP 的离线 pytest、Python 编译和差异检查；运行时 FireTuner 脚本明确不在静态收集范围内。本轮不启动游戏。Round129 post backup：`C:\Users\Administrator\Documents\Civ6_GrandCampaign_Backups\20261007-round129-static-gate-docs-post`。

## Round 127：static-first / MCP 构建手册（2026-10-07）

Research 新增 `docs/37-static-first-mcp-playbook-20261007.md`，固化 UI、事务 adapter 和 MCP 静态证据边界；Endgame 继续保持只读总览与关闭的原生事务 gate。本轮不启动游戏。

## Round 128：MCP 存档清理改为可恢复归档（2026-10-07）

MCP 的旧存档清理现在只做 `_abandoned_mcp` 移动归档；Endgame 继续保持只读 UI 和关闭的原生事务 gate。本轮不启动游戏。

## Round 129：MCP telemetry 清理改为可恢复归档（2026-10-07）

MCP 的 diary/telemetry 清理现在也只做批次移动归档；Endgame 继续保持只读 UI 和关闭的原生事务 gate。本轮不启动游戏。

## Round 130：总览自动高度测量（2026-10-07）

总览面板刷新时会先安全调用自动尺寸计算，再读取 `Summary`、`Notice`、档案行 `Details` 和底部状态的高度；本地化文本变长时，提示区、滚动区和行背景会按实际测量重新排列，减少重叠和截断风险。新增离线回归后总览 UI 为 `47/47`，Research 全套为 `499/499`。本轮不启动游戏，静态几何合同仍不等同于原生绘制证据。

## Round 131：UI 控件引用交叉检查（2026-10-07）

Research 的 UI 合同验证器现在会自动核对所有 Endgame UI companion Lua 的 `Controls.*` 与 XML `ID`、`BuildInstanceForControl()` 与 XML `Instance Name`；这补上了“manifest 存在但 Lua/XML 控件名不匹配”的静态缺口。四层 UI 仍保持左上角入口、只读总览、受保护确认和隐藏指标桥，本轮不启动游戏。

## Round 132：MCP 逐 state UI 证据定位（2026-10-07）

MCP 的只读 UI probe 汇总现在保留每个候选 state 的名称、索引和证据等级，后续可直接定位左上角入口、总览面板、确认弹窗或指标桥对应的运行时 context。该证据仍不等同于原生 action 已绘制或附庸事务已生效，本轮不启动游戏。

## Round 133：总览数据链静态合同（2026-10-07）

Research 新增总览数据合同校验，交叉核对本项目 `EC_OverviewModel.lua` 的 view/entry 字段、`EC_OverviewPanel.lua` 的读取字段和 `EC_Text.xml` 的中英文本地化键。总览仍固定为只读：`AttachAvailable=false`、`RestoreAvailable=false`，面板/模型不包含事务写入 API。该检查证明源码数据链一致，不证明原生进程已绘制窗口或真实附庸事务已接通；本轮不启动游戏。

## Round 134：LaunchBar 原生资产合同（2026-10-07）

Research UI 合同现在还对照本机 Steam 原版 `LaunchBar.xml`/`PartialScreenHooks.xml`，锁定共享按钮栈、背景容器和三项复用纹理。入口 XML/Lua 仍只追加自己的实例，不替换其他按钮；本轮只做静态检查，不宣称原生窗口已绘制。


## Round 135：MCP UI surface 定位摘要（2026-10-07）

MCP 只读 UI probe 现在可以按 state 名称和已读控件定位总览入口、附庸面板、确认弹窗与指标桥；该摘要只改善后续一次性验收的查找效率，仍不把 state 名称或控件存在解释为原生 UI 已绘制。本轮不启动游戏。

## Round 136：MCP UI surface 状态摘要（2026-10-07）

MCP 只读探针现在为总览入口、面板、确认弹窗和指标桥输出候选数与最高证据等级；`candidate_count=0` 不被解释为模组未启用。本轮不启动游戏。

## Round 137：HTTP UI 验收入口同步（2026-10-07）

后续原生 UI 检验使用 MCP 的单一 HTTP 验收脚本读取 surface 状态；Endgame 继续不在静态阶段接入事务 adapter 或提交按钮。本轮不启动游戏。

## Round 138：MCP UI surface 跨仓库合同同步（2026-10-07）

Research 新增跨仓库静态检查，确认 `EC_ConsentUI`、`EC_MetricBridgeUI`、`EC_OverviewLaunchUI`、`EC_OverviewPanelUI` 四个 action 与 MCP 六个 surface 名称保持一致。Endgame UI 仍是只读/关闭事务 gate；本轮不启动游戏。

## Round 139：实机日志 UI 诊断（2026-10-07）

本次实机日志确认四个 Endgame context 均加载，`EC_OverviewPanel` 多次成功打开/关闭；第 64 回合状态为 `awakening_enabled=true`、`awakening_dry_run=true`、`metric_bridge=false`，尚未到第 120 回合门槛，因此空档案和关闭统计属于配置预期。将觉醒摘要从“暂不可用”改为“尚未达到触发门槛”，并修复 LaunchBar 卸载时 ButtonStack 已消失造成的日志噪声。本轮不重复启动游戏。

## 本轮可玩验收同步（2026-10-07）

总览行为48/48、44 Lua compile-only、UI/本地化/项目结构及Stability图标合同通过；命令和恢复点见 Research PROJECT Round149。仅表示静态验证通过，尚未实机复测；完整可玩缺口按文档42执行。
