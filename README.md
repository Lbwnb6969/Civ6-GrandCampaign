# Civ6 GrandCampaign

两个生产用 Civilization VI 模组的合并仓库：

- `Civ6_GrandCampaign_Endgame/`：后期觉醒 AI、战争、附庸、胜利限制与生产规则。
- `Civ6_GrandCampaign_Stability/`：超大地图稳定性、卫星分批开图、万神殿后备和自然奇观安全模式。

两个模组在游戏中保持独立加载；目录合并只用于版本同步和发布管理。`TestFlow` 是测试专用模组，没有上传到本仓库。

## 安装

将两个子目录复制到 Civilization VI 的 Mods 目录，并在游戏内启用对应 `.modinfo` 模组。两个模组都依赖 Gathering Storm；Endgame 的测试开关默认关闭。

## 当前验收状态

候选 AI 取全体 AI 中距离玩家最远 30%与综合实力前 30%的交集。觉醒层的普通产能、军事产能、粮食、金币、科技和文化均为 `+60%`；可选军事 doctrine 为基础军事产能 `+20%`、战时额外 `+40%`、军购折扣 `15%/25%`。原生 MCP 测试已验证真实战争、吞城、AI 自动附庸、四类 AI 胜利、分数胜利、保存重载和 YnAMP 大图基线。

隐藏小数生产、完整实体 UI、自然长局的全类型后期平衡以及多人/热座/云外部会话仍是明确边界，详见 Endgame 的 `PROJECT.md` 和 `docs/81-final-acceptance-matrix-native-20261012.md`。

## 来源提交

本仓库内容从本机两个独立 Git 仓库的 clean HEAD 导出，具体来源提交见 `SOURCE_COMMITS.txt`。
