// 排盘选项与出生地持久化（preferences，对齐 PC 版设置）
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { ChartOptions, DEFAULT_OPTIONS, cloneOptions,
  YearStyle, MonthStyle, SiHuaStyle, LeapMonthStyle, DaXianStartStyle, XiaoXianStyle } from './ZiWeiEngine';

const STORE = 'ziwei_options';
const GEO_STORE = 'ziwei_geo';

// 默认值版本号：改过 DEFAULT_OPTIONS 的开关默认值时 +1。
// 升级时把「本轮改默认值的字段」强制刷成新默认（仅一次），之后完全尊重用户设置。
// v2（09-12）：晚子时日 / 真太阳时 默认 false → true。
const DEFAULTS_VER = 2;

export interface GeoInfo {
  longitude: number | null;
  city: string;
}

// 读取全部流派选项（缺省回落 DEFAULT_OPTIONS）
export async function loadOptions(ctx: common.Context): Promise<ChartOptions> {
  try {
    const pf = await preferences.getPreferences(ctx, STORE);
    const o: ChartOptions = cloneOptions(DEFAULT_OPTIONS);
    // 默认值迁移：ver < DEFAULTS_VER 时（含全新安装），被改过默认值的字段
    // 直接沿用 cloneOptions 带出的新默认并落盘版本号；之后走正常读取，
    // 用户在设置页的改动不会被覆盖。
    const ver = pf.getSync('defaultsVer', 1) as number;
    if (ver < DEFAULTS_VER) {
      // 默认值迁移（v2：晚子时日/真太阳时 false→true）：这两个字段沿用
      // cloneOptions 带出的新默认，其余字段照常读用户已有设置，一次性落版本号。
      pf.putSync('defaultsVer', DEFAULTS_VER);
      await pf.flush();
    } else {
      o.lateZiSwitchDay = pf.getSync('lateZiSwitchDay', DEFAULT_OPTIONS.lateZiSwitchDay) as boolean;
      o.useTrueSolarTime = pf.getSync('useTrueSolarTime', DEFAULT_OPTIONS.useTrueSolarTime) as boolean;
    }
    o.yearStyle = pf.getSync('yearStyle', DEFAULT_OPTIONS.yearStyle) as YearStyle;
    o.monthStyle = pf.getSync('monthStyle', DEFAULT_OPTIONS.monthStyle) as MonthStyle;
    o.siHuaStyle = pf.getSync('siHuaStyle', DEFAULT_OPTIONS.siHuaStyle) as SiHuaStyle;
    o.leapMonthStyle = pf.getSync('leapMonthStyle', DEFAULT_OPTIONS.leapMonthStyle) as LeapMonthStyle;
    o.daXianStartStyle = pf.getSync('daXianStartStyle', DEFAULT_OPTIONS.daXianStartStyle) as DaXianStartStyle;
    o.xiaoXianStyle = pf.getSync('xiaoXianStyle', DEFAULT_OPTIONS.xiaoXianStyle) as XiaoXianStyle;
    o.showShenSha = pf.getSync('showShenSha', DEFAULT_OPTIONS.showShenSha) as boolean;
    o.showExtraShenSha = pf.getSync('showExtraShenSha', DEFAULT_OPTIONS.showExtraShenSha) as boolean;
    o.showBrightness = pf.getSync('showBrightness', DEFAULT_OPTIONS.showBrightness) as boolean;
    o.showTwelveShen = pf.getSync('showTwelveShen', DEFAULT_OPTIONS.showTwelveShen) as boolean;
    o.showLiuNianFull = pf.getSync('showLiuNianFull', DEFAULT_OPTIONS.showLiuNianFull) as boolean;
    return o;
  } catch (error) {
    // 如果读取失败，返回默认选项
    return cloneOptions(DEFAULT_OPTIONS);
  }
}

// 保存全部流派选项
export async function saveOptions(ctx: common.Context, o: ChartOptions): Promise<void> {
  try {
    const pf = await preferences.getPreferences(ctx, STORE);
    pf.putSync('lateZiSwitchDay', o.lateZiSwitchDay);
    pf.putSync('yearStyle', o.yearStyle);
    pf.putSync('monthStyle', o.monthStyle);
    pf.putSync('siHuaStyle', o.siHuaStyle);
    pf.putSync('useTrueSolarTime', o.useTrueSolarTime);
    pf.putSync('leapMonthStyle', o.leapMonthStyle);
    pf.putSync('daXianStartStyle', o.daXianStartStyle);
    pf.putSync('xiaoXianStyle', o.xiaoXianStyle);
    pf.putSync('showShenSha', o.showShenSha);
    pf.putSync('showExtraShenSha', o.showExtraShenSha);
    pf.putSync('showBrightness', o.showBrightness);
    pf.putSync('showTwelveShen', o.showTwelveShen);
    pf.putSync('showLiuNianFull', o.showLiuNianFull);
    await pf.flush();
  } catch (error) {
    // 静默处理保存失败，避免应用崩溃
    console.error('Failed to save options:', error);
  }
}

export async function loadGeo(ctx: common.Context): Promise<GeoInfo> {
  try {
    const pf = await preferences.getPreferences(ctx, GEO_STORE);
    // 哨兵用 999（超出合法经度 ±180）：原用 -1 会把西经（如纽约 -74）误判成「未设置」
    const lon = pf.getSync('longitude', 999) as number;
    const city = pf.getSync('city', '') as string;
    return { longitude: (lon > 180 || lon < -180) ? null : lon, city: city };
  } catch (error) {
    // 读取失败返回默认地理信息
    return { longitude: null, city: '' };
  }
}

export async function saveGeo(ctx: common.Context, g: GeoInfo): Promise<void> {
  try {
    const pf = await preferences.getPreferences(ctx, GEO_STORE);
    pf.putSync('longitude', g.longitude == null ? 999 : g.longitude);
    pf.putSync('city', g.city);
    await pf.flush();
  } catch (error) {
    // 静默处理保存失败
    console.error('Failed to save geo info:', error);
  }
}
