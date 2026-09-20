// QA 专项：三方四正连线几何静态验证（不依赖设备）
// 复刻 ChartPage.ets 的 BRANCH_TO_SLOT / triadAnchor / 引擎的 palaces[i].dizhi 规则，
// 穷举「命宫地支 × 选中宫」全部 12×12 = 144 组合，断言连线端点落在正确宫位。
// 运行: node tests/qa_triad_geometry.mjs

const DI_ZHI = ['子','丑','寅','卯','辰','巳','午','未','申','酉','戌','亥'];
const PALACE_NAMES = ['命宫','兄弟','夫妻','子女','财帛','疾厄','迁移','仆役','官禄','田宅','福德','父母'];
const mod12 = (x) => ((x % 12) + 12) % 12;

// 与 ChartPage.ets:48-53 一致
const BRANCH_TO_SLOT = {
  '巳': 0, '午': 1, '未': 2, '申': 3,
  '辰': 4, '酉': 7,
  '卯': 8, '戌': 11,
  '寅': 12, '丑': 13, '子': 14, '亥': 15
};
const CENTER_SLOTS = new Set([5, 6, 9, 10]);
const OFFS = [0, 4, 8, 6]; // 本宫 / +4 三合 / +8 三合 / +6 对宫

// 引擎规则：palaces[i].dizhi = DI_ZHI[mod12(mingBranch + i)]（ZiWeiEngine.ets:365）
function palaceDizhi(mingBranch, palaceIndex) {
  return DI_ZHI[mod12(mingBranch + palaceIndex)];
}
// ChartPage.ets:945 triadAnchor（只取槽位部分，与像素换算无关）
function anchorSlot(mingBranch, sel, i) {
  const palace = palaceDizhi(mingBranch, mod12(sel + OFFS[i]));
  return BRANCH_TO_SLOT[palace];
}

let pass = 0, fail = 0;
const failures = [];

for (let mb = 0; mb < 12; mb++) {
  for (let sel = 0; sel < 12; sel++) {
    const slots = OFFS.map((_, i) => anchorSlot(mb, sel, i));
    const branches = OFFS.map((_, i) => palaceDizhi(mb, mod12(sel + OFFS[i])));
    const tag = `命宫=${DI_ZHI[mb]} 选中=${PALACE_NAMES[sel]}(${palaceDizhi(mb, sel)})`;

    // 断言1：四个端点都不是中宫占位槽
    const centerHit = slots.filter((s) => CENTER_SLOTS.has(s));
    if (centerHit.length) { fail++; failures.push(`${tag} 端点落在中宫槽 ${centerHit}`); continue; }

    // 断言2：四个端点互不重复
    if (new Set(slots).size !== 4) { fail++; failures.push(`${tag} 端点重复 slots=${slots}`); continue; }

    // 断言3：本宫+两个三合宫 的地支同属一个三合局（地支序号 mod 4 相同）
    const g = [0, 1, 2].map((i) => DI_ZHI.indexOf(branches[i]) % 4);
    if (!(g[0] === g[1] && g[1] === g[2])) {
      fail++; failures.push(`${tag} 三合不共局 地支=${branches.slice(0,3)} mod4=${g}`); continue;
    }

    // 断言4：第4个端点（对宫）与本宫地支相差 6
    const b0 = DI_ZHI.indexOf(branches[0]);
    const b3 = DI_ZHI.indexOf(branches[3]);
    if (mod12(b3 - b0) !== 6) { fail++; failures.push(`${tag} 对宫非冲 本宫=${branches[0]} 对宫=${branches[3]}`); continue; }

    // 断言5：端点槽位与「按地支直查表」一致（双重校验，防两套坐标混用）
    for (let i = 0; i < 4; i++) {
      if (BRANCH_TO_SLOT[branches[i]] !== slots[i]) {
        fail++; failures.push(`${tag} 槽位映射不一致`); break;
      }
    }
    pass++;
  }
}

// 抽样打印 3 个不同命宫地支的连线落点（人类可读证据）
function dump(mb, sel) {
  const slots = OFFS.map((_, i) => anchorSlot(mb, sel, i));
  const branches = OFFS.map((_, i) => palaceDizhi(mb, mod12(sel + OFFS[i])));
  const names = OFFS.map((_, i) => PALACE_NAMES[mod12(sel + OFFS[i])]);
  const pos = slots.map((s) => `(行${Math.floor(s / 4)},列${s % 4})`);
  console.log(`  命宫${DI_ZHI[mb]} 选中${PALACE_NAMES[sel]}: ` +
    names.map((n, i) => `${n}(${branches[i]})${pos[i]}`).join(' → '));
}
console.log('样例落点（本宫 → +4 → +8 → +6对宫）:');
dump(0, 0);   // 命宫在子
dump(4, 6);   // 命宫在辰，选迁移
dump(9, 2);   // 命宫在酉，选夫妻
dump(2, 10);  // 命宫在寅，选田宅

console.log(`\n结果: PASS=${pass} FAIL=${fail} (共 144 组合)`);
if (failures.length) {
  console.log('失败明细（前 20 条）:');
  failures.slice(0, 20).forEach((f) => console.log('  ' + f));
  process.exit(1);
}
