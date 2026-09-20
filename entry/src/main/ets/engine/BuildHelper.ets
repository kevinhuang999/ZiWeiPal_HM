// 从路由参数构造排盘（统一 solar/lunar 分支，供 ChartPage/DetailPage 复用）
import { buildChart, ChartResult, ChartOptions } from './ZiWeiEngine';

export interface ChartInputs {
  calendarType: string; // 'solar' | 'lunar'
  gender: string;
  solarYear: number; solarMonth: number; solarDay: number;
  lunarYear: number; lunarMonth: number; lunarDay: number; isLeap: boolean;
  hour: number; minute: number;
  options?: ChartOptions;
  longitude?: number | null;
}

export function buildFromInputs(input: ChartInputs): ChartResult | null {
  if (input.calendarType === 'solar') {
    return buildChart({
      solarYear: input.solarYear,
      solarMonth: input.solarMonth,
      solarDay: input.solarDay,
      hour: input.hour,
      minute: input.minute,
      gender: input.gender,
      longitude: input.longitude,
      options: input.options
    });
  }
  return buildChart({
    lunarYear: input.lunarYear,
    lunarMonth: input.lunarMonth,
    lunarDay: input.lunarDay,
    isLeap: input.isLeap,
    hour: input.hour,
    minute: input.minute,
    gender: input.gender,
    longitude: input.longitude,
    options: input.options
  });
}

// 三方四正：本宫 + 三合(±4) + 对宫(+6)，下标为命盘宫序
export function sanFangSiZheng(k: number): number[] {
  return [k, (k + 4) % 12, (k + 8) % 12, (k + 6) % 12];
}
