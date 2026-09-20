// 今日流日运势：在既有引擎输出之上叠一层「流日」推演，供悬浮窗（闪控窗）取数。
//
// ★ 刻意不动 engine/ZiWeiEngine.ets：该文件已对拍 98/98 例《天纪》讲义，
//   流日属于叠加层，放在本文件里算，避免污染已验收的排盘主链。
//
// 口径（三合派通说，与引擎既有流年/流月同一体系）：
//   流年命宫 = 年支落宫（引擎已算 liuNianMingIndex）
//   流月命宫 = 流年斗君起正月，顺数至当月（引擎在 liuNianYear 非空时已填 palaces[].liuYue）
//   流日命宫 = 从流月命宫起初一，顺行至当日（不分男女，恒顺行）
//   流日四化 = 取当日日柱天干，查四化表（与生年/流年四化同一张表）
import { buildFromInputs, ChartInputs } from './BuildHelper';
import { ChartResult, ChartOptions, StarCell, cloneOptions } from './ZiWeiEngine';
import { solar2lunar, dayPillarIndex, LunarResult } from './CalendarUtil';
import { DI_ZHI, TIAN_GAN, mod12 } from './Constants';
import { SI_HUA_NAN_PAI, SI_HUA_ZHONG_ZHOU } from './AnXingTables';

// 一条四化：类型（禄/权/科/忌）+ 星名
export interface SiHuaItem {
  type: string;
  star: string;
}

export interface DailyFortune {
  solarText: string;      // 2026-09-20
  lunarText: string;      // 八月初九（不含「农历」前缀，由界面拼）
  dayGanZhi: string;      // 日柱干支，如「丁卯」
  liuYuePalace: string;   // 流月命宫落在本命盘的哪个宫
  liuYueBranch: string;   // 该宫地支
  liuRiPalace: string;    // 流日命宫落在本命盘的哪个宫
  liuRiBranch: string;
  liuRiMainStars: string; // 该宫本命主星（顿号分隔；空宫给空串）
  siHua: SiHuaItem[];     // 流日四化，固定 4 条
}

const CN_MONTH: string[] = ['正', '二', '三', '四', '五', '六', '七', '八', '九', '十', '冬', '腊'];
const CN_DAY_PREFIX: string[] = ['初', '十', '廿', '三'];
const CN_DAY_NUM: string[] = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];

// 农历日中文：初一…初十 / 十一…二十 / 廿一…三十
function lunarDayCn(d: number): string {
  if (d === 10) { return '初十'; }
  if (d === 20) { return '二十'; }
  if (d === 30) { return '三十'; }
  return CN_DAY_PREFIX[Math.floor(d / 10)] + CN_DAY_NUM[(d % 10) - 1];
}

function pad2(n: number): string {
  return n < 10 ? '0' + n.toString() : n.toString();
}

function palaceByBranch(c: ChartResult, branch: string): StarCell | null {
  for (const p of c.palaces) {
    if (p.dizhi === branch) {
      return p;
    }
  }
  return null;
}

// 本命主星名（顿号分隔），空宫返回空串
function mainStarText(p: StarCell | null): string {
  if (!p || p.mainStars.length === 0) {
    return '';
  }
  const names: string[] = [];
  for (const s of p.mainStars) {
    names.push(s.name);
  }
  return names.join('、');
}

/**
 * 计算「今日流日」。
 * @param input 最近一次排盘的生辰参数
 * @param opts  排盘口径（四化流派等）
 * @param today 目标日期，默认取系统当天
 * @returns 数据不全 / 日期超出引擎范围时返回 null，由调用方决定怎么提示
 */
export function computeDailyFortune(input: ChartInputs, opts: ChartOptions,
  today: Date): DailyFortune | null {
  const y: number = today.getFullYear();
  const m: number = today.getMonth() + 1;
  const d: number = today.getDate();
  const lunar: LunarResult | null = solar2lunar(y, m, d);
  if (!lunar) {
    return null;
  }
  // 流月依赖流年，必须把 liuNianYear 置为今年；小限与本窗口无关，清掉免得白算
  const o: ChartOptions = cloneOptions(opts);
  o.liuNianYear = y;
  o.currentAge = null;
  const c: ChartResult | null = buildFromInputs({
    calendarType: input.calendarType,
    gender: input.gender,
    solarYear: input.solarYear,
    solarMonth: input.solarMonth,
    solarDay: input.solarDay,
    lunarYear: input.lunarYear,
    lunarMonth: input.lunarMonth,
    lunarDay: input.lunarDay,
    isLeap: input.isLeap,
    hour: input.hour,
    minute: input.minute,
    options: o,
    longitude: input.longitude
  });
  if (!c) {
    return null;
  }
  // 流月命宫：引擎按 liuYue = 0 起正月顺排，故当月（农历月序）落在 liuYue === lMonth-1
  let liuYueCell: StarCell | null = null;
  for (const p of c.palaces) {
    if (p.liuYue === lunar.lMonth - 1) {
      liuYueCell = p;
      break;
    }
  }
  if (!liuYueCell) {
    return null;
  }
  // 流日命宫：从流月命宫起初一，顺行至当日
  const riBranchIdx: number = mod12(DI_ZHI.indexOf(liuYueCell.dizhi) + lunar.lDay - 1);
  const riBranch: string = DI_ZHI[riBranchIdx];
  const liuRiCell: StarCell | null = palaceByBranch(c, riBranch);
  if (!liuRiCell) {
    return null;
  }
  // 流日四化：当日日柱天干
  const dayGanIdx: number = dayPillarIndex(y, m, d) % 10;
  const row: string[] = (opts.siHuaStyle === 'ZhongZhou' ? SI_HUA_ZHONG_ZHOU : SI_HUA_NAN_PAI)[dayGanIdx];
  const siHua: SiHuaItem[] = [
    { type: '禄', star: row[0] },
    { type: '权', star: row[1] },
    { type: '科', star: row[2] },
    { type: '忌', star: row[3] }
  ];
  return {
    solarText: `${y}-${pad2(m)}-${pad2(d)}`,
    lunarText: (lunar.isLeap ? '闰' : '') + CN_MONTH[lunar.lMonth - 1] + '月' + lunarDayCn(lunar.lDay),
    dayGanZhi: TIAN_GAN[dayGanIdx] + DI_ZHI[((dayPillarIndex(y, m, d) % 12) + 12) % 12],
    liuYuePalace: liuYueCell.palaceName,
    liuYueBranch: liuYueCell.dizhi,
    liuRiPalace: liuRiCell.palaceName,
    liuRiBranch: riBranch,
    liuRiMainStars: mainStarText(liuRiCell),
    siHua: siHua
  };
}
