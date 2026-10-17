// Two headless Chromium pages on the web export: one hosts, one joins (PeerJS, WebRTC data channel), both run
// test/net/drive.gd; prints both consoles' CHECK / DRIVE / NET lines and saves screenshots at the given seconds.
// usage: node two_pages.mjs <base url of index.html> <out dir> [extra query] [shots "s1,s2,..."] [total secs]
// e.g. node two_pages.mjs http://127.0.0.1:8741/build/web/index.html out "peer=127.0.0.1:9000&peerjs=peerjs.min.js"
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
const [base, out, extra = '', shotsArg = '25,33,45,60', total = '75'] = process.argv.slice(2);
const shots = shotsArg.split(',').map(Number);
setTimeout(() => { console.log('TIMED OUT'); process.exit(1); }, (+total + 60) * 1000);
const b = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
  args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'] });
const q = (role) => base + '?' + role + '&netdrive=res://test/net/drive.gd&netstate' + (extra ? '&' + extra : '');
async function page(name, url) {
  const ctx = await b.newContext({ viewport: { width: 960, height: 540 } });
  const p = await ctx.newPage();
  p.on('console', m => { const t = m.text(); if (/CHECK|DRIVE|Net:|ERROR|error|SCRIPT/.test(t) || (/^NET /.test(t) && Math.random() < 0.1)) console.log(name + ': ' + t.slice(0, 300)); });
  p.on('pageerror', e => console.log(name + ' pageerror: ' + e.message));
  await p.goto(url);
  return p;
}
const host = await page('host', q('host=TEST'));
await new Promise(r => setTimeout(r, 6000));
const guest = await page('guest', q('join=TEST'));
const t0 = Date.now();
for (const s of shots) {
  const wait = s * 1000 - (Date.now() - t0);
  if (wait > 0) await new Promise(r => setTimeout(r, wait));
  await host.screenshot({ path: `${out}/host_${s}.png` });
  await guest.screenshot({ path: `${out}/guest_${s}.png` });
  console.log('shot', s);
}
const rest = +total * 1000 - (Date.now() - t0);
if (rest > 0) await new Promise(r => setTimeout(r, rest));
await b.close(); process.exit(0);
