// usage: node shots.mjs <base url> <outdir> <name>=<query> ...   (one page load per shot)
// e.g. node shots.mjs http://127.0.0.1:8731/build/web/index.html out noon="hour=12" night_fp="hour=23&view=fp"
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
const [base, outdir, ...shots] = process.argv.slice(2);
const wait = +(process.env.WAIT || 16000);
const b = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--ignore-gpu-blocklist'] });
for (const s of shots) {
  const i = s.indexOf('=');
  const name = s.slice(0, i), q = s.slice(i + 1);
  const p = await b.newPage({ viewport: { width: +(process.env.W || 1280), height: +(process.env.H || 720) } });
  const logs = []; p.on('console', m => logs.push(m.type() + ': ' + m.text().slice(0, 300))); p.on('pageerror', e => logs.push('pageerror: ' + e.message));
  await p.goto(base + '?' + q); await p.waitForTimeout(wait);
  await p.screenshot({ path: `${outdir}/${name}.png` });
  console.log(`== ${name} (${q})\n` + logs.filter(l => !/^debug|^verbose/.test(l) && !/WorldBuilder/.test(l)).slice(-12).join('\n'));
  await p.close();
}
await b.close(); process.exit(0);
