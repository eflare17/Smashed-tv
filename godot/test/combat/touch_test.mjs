// Touch controls in the web build: node touch_test.mjs <url> <out.png>
// Starts a run (Enter), then drags the left-half move stick right and holds the right-half aim stick.
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
const [url, out] = process.argv.slice(2);
setTimeout(() => { console.log('TIMED OUT'); process.exit(1); }, 120000);
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--ignore-gpu-blocklist'] });
const ctx = await b.newContext({ viewport: { width: 1280, height: 720 }, hasTouch: true });
const p = await ctx.newPage();
const logs = []; p.on('console', m => { if (/FIGHT|rror/.test(m.text())) logs.push(m.text().slice(0, 200)); });
await p.goto(url); await p.waitForTimeout(9000);
await p.keyboard.press('Enter'); await p.waitForTimeout(2500);
const cdp = await ctx.newCDPSession(p);
const t = (type, pts) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: pts });
await t('touchStart', [{ x: 300, y: 450, id: 1 }]);
for (let i = 1; i <= 6; i++) { await t('touchMove', [{ x: 300 + i * 12, y: 450, id: 1 }]); await p.waitForTimeout(60); }
await p.waitForTimeout(1500);
await t('touchStart', [{ x: 300 + 72, y: 450, id: 1 }, { x: 1000, y: 300, id: 2 }]);
for (let i = 1; i <= 5; i++) { await t('touchMove', [{ x: 372, y: 450, id: 1 }, { x: 1000 + i * 10, y: 300 - i * 6, id: 2 }]); await p.waitForTimeout(60); }
await p.waitForTimeout(1500);
await p.screenshot({ path: out });
await t('touchEnd', []);
await p.waitForTimeout(1200);
console.log(logs.slice(-8).join('\n'));
await b.close(); process.exit(0);
