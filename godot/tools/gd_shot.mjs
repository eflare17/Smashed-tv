// usage: node gd_shot.mjs <url> <out.png> [waitMs]
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
const [url, out, wait] = process.argv.slice(2);
setTimeout(() => { console.log('TIMED OUT'); process.exit(1); }, 120000);
const b = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--ignore-gpu-blocklist'] });
const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
const logs = []; p.on('console', m => logs.push(m.type() + ': ' + m.text().slice(0, 200))); p.on('pageerror', e => logs.push('pageerror: ' + e.message));
await p.goto(url); await p.waitForTimeout(+wait || 12000);
await p.screenshot({ path: out });
console.log(logs.filter(l => !/^debug|^verbose/.test(l)).slice(-15).join('\n'));
await b.close(); process.exit(0);
