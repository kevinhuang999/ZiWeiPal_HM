// 节气计算（对齐 PC 版 Calendar/SolarTerms.cs，Meeus 太阳视黄经 + 牛顿迭代）
// 用于「立春换年」「节气换月」流派选项。东八区假定。
import { julianDayNumber } from './CalendarUtil';

// 平气近似初值（牛顿迭代种子），下标 0-23 对应 立春…大寒
const APPROX_DAY_OF_YEAR: number[] = [
  35, 50, 64, 79, 94, 110, 126, 141, 156, 172, 188, 204,
  219, 235, 251, 266, 281, 297, 311, 326, 341, 356, 371, 386
];

function normalizeDeg(d: number): number {
  d = d % 360;
  if (d < 0) d += 360;
  return d;
}

function sunApparentLongitude(jd: number): number {
  const T = (jd - 2451545.0) / 36525.0;
  const L0 = 280.46646 + 36000.76983 * T + 0.0003032 * T * T;
  const M = normalizeDeg(357.52911 + 35999.05029 * T - 0.0001537 * T * T);
  const rad = Math.PI / 180.0;
  const C = (1.914602 - 0.004817 * T - 0.000014 * T * T) * Math.sin(M * rad)
    + (0.019993 - 0.000101 * T) * Math.sin(2 * M * rad)
    + 0.000289 * Math.sin(3 * M * rad);
  const trueLon = normalizeDeg(L0 + C);
  const omega = normalizeDeg(125.04 - 1934.136 * T);
  const appLon = normalizeDeg(trueLon - 0.00569 - 0.00478 * Math.sin(omega * rad));
  return normalizeDeg(appLon);
}

// 计算第 index 个节气（0=立春 … 23=大寒）的儒略日
export function solarTermJd(year: number, index: number): number {
  let jd = julianDayNumber(year, 1, 1) + 0.5 + APPROX_DAY_OF_YEAR[index];
  const targetLon = 315.0 + 15.0 * index;
  for (let i = 0; i < 3; i++) {
    const lon = sunApparentLongitude(jd);
    let d = normalizeDeg(targetLon - lon);
    if (d > 180) d -= 360;
    jd += d / 0.985647;
  }
  return jd;
}

// 东八区本地时刻（ArkTS 不支持对象字面量作返回类型，须显式声明 interface）
export interface JdLocal {
  year: number;
  month: number;
  day: number;
  hour: number;
}

// 儒略日 → 东八区本地 {year, month, day, hour(含小数)}
export function jdToLocal(jd: number): JdLocal {
  const ms = (jd - 2440587.5) * 86400000 + 8 * 3600000; // +8h 东八区
  const dt = new Date(ms);
  return {
    year: dt.getUTCFullYear(),
    month: dt.getUTCMonth() + 1,
    day: dt.getUTCDate(),
    hour: dt.getUTCHours() + dt.getUTCMinutes() / 60 + dt.getUTCSeconds() / 3600
  };
}

// 指定年的第 k 个「节」（k=0..11 对应 立春,惊蛰,…小寒）的儒略日
export function jieMomentJd(year: number, k: number): number {
  return solarTermJd(year, k * 2);
}

// 是否已过立春（用于年柱换年）
export function afterLiChun(year: number, jd: number): boolean {
  return jd >= jieMomentJd(year, 0);
}
