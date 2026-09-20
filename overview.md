# ZiWeiPal_HM（紫微排盘 HarmonyOS）— 项目概览

## 项目状态（2026-09-01）
**已编译通过（BUILD SUCCESSFUL）**，HAP 产物 `entry/build/default/outputs/default/entry-default-unsigned.hap`（512K）。

- 新建工程：`source/ZiWeiPal_HM`（IDE 模板，API 版本以工程为准，本地 SDK 26.0.0 兼容编译 6.1.0(23)）
- 引擎算法：完整对齐 PC 版 `source/ZiWeiPal`（Node 校验 **98/98 PASS**，含倪师《天纪》38 例外部反推）
- 功能：14 主星 + 辅星 14 + 四化两派 + 庙旺 + 神煞 + 十二神 + 大限/小限/流年 + 真太阳时 + 流派选项 + 三视图 + 三方四正 + 星曜属性 + Markdown 导出 + 中英双语
- 已砍：AI 解析（原 SSE 联网），全程离线

## 颜色与 UI（2026-09-02 改版 v2「古纸朱砂·环抱」+ 当日三波迭代，当前版本）
- **配色令牌收口完成**：`engine/Constants.ets` COLORS 现 **26 色**（v2 新增 greenSoft/purpleSoft，评审修复新增 goldInk/centerBg/toastBg/primaryGlow/primaryGlowSoft，收口新增 heroBg/shadowSoft/scrim）。**4 页面硬编码 hex 清零**（Grep 终检 = 0），改主题只动 Constants.ets 一处。
- **四页全部重写**（设计方案：`design/index.html` 高保真稿 + `design/UI设计方案_v2.md` 实施规范）：
  - **首页**：品牌头（朱砂「紫」印 Logo + 右上设置钮）；单卡三行表单（历法分段/生辰一行数字点击弹轮盘/性别分段）；农历⇄公历自动换算提示 + 时辰显示；「最近排盘」（Preferences 存 JSON，最多 3 条，点击直达 + **清空按钮含确认框**）；页脚离线声明。
  - **命盘页（核心）**：4×3 平铺 → **4×4 环抱布局**（外圈 12 宫按地支定位 BRANCH_TO_SLOT 映射；中宫跨 2×2 = 朱印 + 五行局/命主身主/四柱/紫微天府，**描金边**，大限/流年视图联动换内容）；四化徽章四色色块 + 底部四化横条（随视图切换生年/流年/大限）；**点宫格=选中+Toast 提示三方四正，再点同宫=进详情**；**三方四正宫极淡蓝底**（原仅描边）；盘面上方**轻提示行**；分段控件切三视图，右侧小钮弹层选年份/年龄。
  - **详情页**：宫位 Hero（大字主星 25px + 命/身/大限/三方四正徽章 + 宫干支藏干 + 三方四正列名）；分组卡（主星属性默认展示/辅星/宫位信息键值行/神煞）；自定义返回钮。
  - **设置页**：三组卡（基础：真太阳时+出生地｜排盘口径：6 项行内值 › 点开底部浮层｜显示开关 5 项）+ 关于卡（版本/98 例校验）；每项副说明；城市浮层支持中文/拼音搜索。
- **评审与修复（同日）**：独立评审 PASS_WITH_NOTES（报告 `design/UI评审报告_2026-09-02.md`）。P1 修复：日份 1..30 → **1..31**（非法组合 convertFail 兜底）。P2 修复：装饰色全收令牌 + 修品牌头阴影笔误 #52199999→#529B2E23；EntryAbility **强制 COLOR_MODE_LIGHT**（国风浅色刻意设计）+ 状态栏深色文字。
- **多语言**：string key 累计 88（v2 +15，增强 +4：tap_hint/clear_recent/clear_confirm/clear_recent_msg），base/zh_CN/en_US 三语完全对齐（Python 校验）。
- **ArkTS 踩坑（本次新增）**：①`Button` 不支持 `.letterSpacing()`（Text 专属）②`@State` 数组须整体替换 ③浮层 = `Stack + if` 条件渲染 ④**`AlertDialog.show` 的 `cancel` 参数是 VoidCallback（对话框关闭回调）不是取消按钮对象**，传 `{value,action}` 必报类型错 ⑤AlertDialogParamWithConfirm 的 `title`/`message` 均必填，缺 message 报错。
- 编译：BUILD SUCCESSFUL（2026-09-02 终版），HAP 产物 unsigned 650K / signed 687K。git：`9057ed2`(v2) → `5ad66aa`(P1+P2) → `464055f`(增强) → `0ab8886`(令牌收口)。

## 颜色与 UI（2026-09-01 改版，已被 09-02 v2 取代）
- 配色 A「古纸朱砂」（黄总从三方案中选定）：古绢米白 `#F8F4EC` + 朱砂 `#9B2E23` + 黛蓝 `#425066` + 竹青 `#5F7D52` + 绛紫 `#8C4356` + 墨 `#33302B`，集中 `Constants.ets` COLORS。v2 沿用。
- Bug 修复（已并入 v2）：首页 `$r()` 拼接 bug 随整页重写消除。

## 验证（无真机）
- 验证清单已重写：`真机回归清单.md`（Previewer + DevEco 模拟器 + Node 三层）
- **待办**：DevEco 自动签名 → 模拟器 Run → 按清单逐项核对 → 截图取景做上架材料 → 9/25 前报激励计划、9/30 前上架

## 关键路径
- 上架指南：`上架指南.md`（含编译命令、锚点、ArkTS 踩坑记录）
- 验证清单：`真机回归清单.md`（无真机版，Previewer + 模拟器 + Node 98/98）
- 引擎：`entry/src/main/ets/engine/`（Constants / AnXingTables / CalendarUtil / SolarTerms / ZiWeiEngine / OptionsStore / BuildHelper）
- 页面：`entry/src/main/ets/pages/`（Index / ChartPage / DetailPage / SettingsPage）
- 组件：`entry/src/main/ets/components/NumberPicker.ets`

## 移植来源
旧工程 `source/ZiWeiPal_HarmonyOS`（引擎算法同源，UI/资源已迁入新工程；旧工程保留作参考，不再迭代）。
