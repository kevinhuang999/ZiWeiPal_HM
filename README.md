# 紫微斗数排盘 · HarmonyOS 原生版

> 一份**纯 ArkTS / ArkUI** 的鸿蒙原生 App 完整实现：自带规则计算引擎、四语言国际化，并集成了 HarmonyOS 7 的**平行视界、应用分栏、悬浮窗（闪控球 ↔ 闪控窗）与华为分享**。
>
> 写给想上手鸿蒙原生开发的同学当参考实现。**零第三方依赖、零联网、零 API Key、零隐私外传**——全部逻辑跑在端侧。

---

## 一、这是什么

一款按传统规则排布星曜与宫位的工具类 App，核心是一个**表驱动的规则计算引擎**。

引擎负责：十二宫位、十四主星、辅星煞星、四化（两派）、庙旺、神煞、十二神、大限 / 小限 / 流年 / 流月 / 流日、真太阳时校正、流派选项（三合 / 飞星、早晚子时、闰月口径）。

界面负责：表单录入 → 命盘三视图 → 宫位详情 → 导出图片 / Markdown → 分享。

> 本文只描述**算法与工程实现**。项目不提供任何预测类服务，纯粹是把一套传统规则用代码表达出来。

## 二、HarmonyOS 7 能力落地（4 项）

| # | 能力 | 实现方式 | 需不需要改页面代码 |
|---|---|---|---|
| ① | **平行视界** | `easy_go.json` 声明式配置（`routerSplit` + `routerSplitOptions`） | 不需要 |
| ② | **应用分栏（1:2 / 2:1）** | 同上配置，`isDraggable` 开拖拽 | 不需要 |
| ③ | **悬浮窗（闪控球 ↔ 闪控窗）** | `@ohos.window.floatView`（API 26）：`create → setUIContext → bind → start` | 需要一个悬浮窗页面 |
| ④ | **华为分享** | `@kit.ShareKit`：`systemShare` 面板 + `harmonyShare.on()` 碰一碰 / 隔空 | 几行调用 |

**两点值得说明**：

- ③ 的 `USE_FLOAT_BALL` / `FLOAT_VIEW` 是 **system_basic 受限权限**，需在 AGC 申请 ACL 并通过后才可声明。本仓库把代码写完整、**默认关闭**（见 `floatview/FloatToday.ets` 的 `GATE_ACL_APPROVED`），避免未获批就声明权限导致 AGC Profile 申请失败。
- ④ 的**「加密分享 / 禁止截屏」是系统分享面板自带的通道**，应用侧不需要写任何加密代码。

## 三、架构

```
UI 层（pages / components）
    │  只做渲染与交互，不碰算法
    ▼
引擎层（engine/）
    │  纯 TypeScript，无 ArkUI 依赖，可单独跑 Node 测试
    ├── ZiWeiEngine.ets      主流程编排（排盘 → 安星 → 四化 → 限运）
    ├── AnXingTables.ets     星曜定位表（表驱动，口诀一一对应）
    ├── CalendarUtil.ets     公历 / 农历 / 干支 / 真太阳时
    ├── SolarTerms.ets       二十四节气
    ├── DailyFortune.ets     流日叠加层（不改动主引擎，独立计算）
    ├── OptionsStore.ets     流派选项持久化
    ├── Constants.ets        颜色 / 常量
    ├── TextConv.ets         简体 → 繁体显示层转换
    └── HantMap.ets          繁简映射表（脚本生成）
```

**「引擎可脱离 UI 单独测试」是这套结构的关键收益**——`tests/engine_node/` 里是引擎的 Node 版副本，可以在命令行直接跑断言，不必开模拟器。

## 四、目录

```
entry/src/main/ets/
  engine/     规则计算引擎（纯 TS）
  pages/      Index / ChartPage / DetailPage / SettingsPage / FloatPage / PrivacyPage
  floatview/  闪控球↔闪控窗控制器
  share/      华为分享封装
entry/src/main/resources/
  base|zh_CN|en_US|zh_Hant/element/string.json   四语言资源
  base/profile/easy_go.json                      平行视界 / 分栏配置
  base/profile/main_pages.json                   页面注册表
tests/        自检脚本（表值对拍 / 引擎行为 / 国际化 / 繁简映射）
```

## 五、快速开始

**环境**：DevEco Studio（HarmonyOS SDK 6.1.0(23) 及以上，本工程 `targetSdkVersion` 为 26.0.0）。

```bash
# 1. 克隆
git clone https://gitee.com/huang-jianhua-gitee/zi-wei-pal_-hm.git
cd zi-wei-pal_-hm

# 2. 用 DevEco Studio 打开工程，先配置签名
#    File > Project Structure > Signing Configs → 勾选 "Automatically generate signature"

# 3. 运行到模拟器或真机
#    选 entry 模块 → Run
```

**命令行构建**（不开 IDE）：

```bash
export JAVA_HOME="<DevEco>/jbr"
export DEVECO_SDK_HOME="<DevEco>/sdk"
export PATH="$JAVA_HOME/bin:$PATH"
"<DevEco>/tools/node/node.exe" "<DevEco>/tools/hvigor/bin/hvigorw.js" \
  --mode module -p product=default assembleHap --no-daemon
```

> 只设 `JAVA_HOME` 不够：打包阶段会去 PATH 里找 `java`，所以 `jbr/bin` 也得进 PATH。

## 六、测试

引擎与资源都有可复跑的断言，不需要设备：

```bash
python tests/verify_tables.py       # 142 条：从源码抓表值，与口诀逐条对拍 + 越界扫描
node   tests/verify_engine.mjs      # 98 条：引擎行为（含 38 例外部分反推样例）
node   tests/verify_daily_fortune.mjs  # 10 条：流日推演公式
node   tests/verify_wenmo.mts       # 100 条：对拍样例盘，逐宫校验
python tests/verify_i18n.py         # 四语言资源键对齐 + 死键检测
python tests/gen_hant_map.py        # 重生成繁简映射表（自带术语对拍 + 幂等性双闸）
```

**为什么值得这么测**：开发过程中曾因「星曜表写错一位」导致 40% 的年份落错宫，而当时的引擎行为测试**全绿**——因为那份测试是算法复刻版，不读源码。后来改成**用正则直接从源码里抓表值去对拍口诀**，才把这类错误钉死。**表驱动的代码，测试必须对着源表测。**

## 七、说明

- 本项目**不上架国内应用商店**。原因不在技术：这类目在国内各商店均属不收录范围（华为《不收录类型》第 28 条）。保留为**参考实现与技术演示**。
- 本仓库**不包含任何签名材料**（证书 / Profile / 密码均已移除），请按第五节自行生成。
- 代码仅供学习参考。项目不提供预测类功能，涉及的传统术语仅作为算法输入存在。

## 八、关于我

13 年 IT 全栈，.NET、Python、Office 自动化（VSTO/VBA/Python）都做，也做 AI 应用实操（智能体开发），主业是帮企业和团队把重复劳动自动化——报表一键生成、数据对接、文档批量处理、工具定制。

本科物理化学、硕士计算机化学，在一线实验室待过 13 年（9 年制药 + 4 年第三方检测），现在主要服务药企、检测机构和实验室：SOP、合规、样本流、仪器数据接口这些词不用你解释。

这几年做得比较多的是这几类：Office 自动化（VSTO/VBA/Python）工具定制、数据对接与 LIMS 咨询、技术陪跑。

不是外包码农，是听得懂业务的自己人。有同类场景的朋友欢迎评论区聊聊，先聊清楚再动手不迟。

## License

MIT
