// A phone screenshot: node phone_shot.mjs <url> <out.png> <portrait|landscape> [waitMs]
// Chromium mobile emulation (390 x 844 or 844 x 390, deviceScaleFactor 2, isMobile, hasTouch); one tap first so
// the game sees a touch (the touch controls show).
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
const [url, out, orient, wait] = process.argv.slice(2);
setTimeout(() => { console.log('TIMED OUT'); process.exit(1); }, 120000);
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--ignore-gpu-blocklist'] });
const vp = orient === 'landscape' ? { width: 844, height: 390 } : { width: 390, height: 844 };
const ctx = await b.newContext({ viewport: vp, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
const p = await ctx.newPage();
const logs = []; p.on('console', m => { if (/rror/.test(m.text())) logs.push(m.text().slice(0, 200)); });
await p.goto(url); await p.waitForTimeout((+wait || 14000) - 2000);
await p.touchscreen.tap(vp.width / 2, vp.height * 0.6); await p.waitForTimeout(2000);
await p.screenshot({ path: out });
console.log(logs.slice(-5).join('\n'));
await b.close(); process.exit(0);
