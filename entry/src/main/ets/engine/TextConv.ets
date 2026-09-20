// 简繁「显示层」转换。
//
// 设计前提：ZiWeiEngine / AnXingTables 里的星名、宫名、十二神等**永远是简体**，
// 转换只发生在渲染这一步。原因是引擎内部要做反查，例如
//   ZiWeiEngine:463  MAIN_STAR_NAMES.indexOf(s.name)
//   DetailPage:17    MAIN_STAR_NAMES.indexOf(name)
// 一旦把数据模型里的星名换成繁体，这些 indexOf 全部返回 -1，庙旺/星曜属性会静默失效。
// 所以：数据层简体不动，显示层按当前语言转换。
//
// hant() 对已经是繁体 / 英文 / 数字 / 标点的字符串是恒等变换 —— HANT_MAP 只收录
// 简体字，繁体字与拉丁字符查不到键，原样返回。因此可以放心地把任何展示字符串
// 丢进来，包括已由资源文件本地化好的文案（繁体资源里的字不在表内，天然免疫）。
//
// 运行时语言来自 i18n 的应用偏好语言（由设置页写入，系统负责持久化），
// 不再自建一套偏好存储，也不做结果缓存 —— 判定就是一次进程内取语言配置，
// 比维护「缓存何时失效」的额外状态更不容易出错。

import { i18n } from '@kit.LocalizationKit';
import { HANT_MAP } from './HantMap';

// 逐字映射。不用 replace 正则：字符表是精确的白名单，逐字查表更直观也更快。
// 查不到键（繁体字/拉丁字符/数字/标点）时 `?? c` 原样返回。
export function toHant(s: string): string {
  let out: string = '';
  for (let i = 0; i < s.length; i++) {
    const c: string = s.charAt(i);
    out += HANT_MAP[c] ?? c;
  }
  return out;
}

// 应用偏好语言是否繁体。
// 繁体判定兜三种写法：zh-Hant / zh-Hant-TW，以及只给地区码的 zh-TW、zh-HK、zh-MO。
export function isHantNow(): boolean {
  let p: string = '';
  try {
    p = i18n.System.getAppPreferredLanguage();
  } catch (e) {
    return false;
  }
  return p.indexOf('Hant') >= 0 || p.indexOf('TW') >= 0
    || p.indexOf('HK') >= 0 || p.indexOf('MO') >= 0;
}

// 显示层简繁：非繁体模式恒等返回，调用方不需要自己判断分支。
// 注意只包「显示」的那一层：ForEach 的 key、以及 sihuaBadgeColor('禄') 这类
// 拿简体字做等值比较的逻辑，一律不要过 hant()。
export function hant(s: string): string {
  return isHantNow() ? toHant(s) : s;
}
