// Plays the web build with real input: node play_test.mjs <url> <outdir>
// Lobby: shoot the dummies with the mouse, switch weapons with the keys; Enter starts a run; fight; R restarts.
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
const [url, out] = process.argv.slice(2);
setTimeout(() => { console.log('TIMED OUT'); process.exit(1); }, 170000);
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--ignore-gpu-blocklist'] });
const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
const logs = []; p.on('console', m => { const t = m.text(); if (!/AudioContext/.test(t)) logs.push(t.slice(0, 220)); }); p.on('pageerror', e => logs.push('pageerror: ' + e.message));
await p.goto(url); await p.waitForTimeout(9000);
const shot = async (n) => { await p.screenshot({ path: `${out}/${n}.png` }); };
// aim right of him (the dummies are east) and hold fire
await p.mouse.move(1100, 330); await p.mouse.down(); await p.waitForTimeout(1500); await p.mouse.up();
await shot('p1_lobby_fire');
await p.keyboard.press('Digit2'); await p.waitForTimeout(300);
await p.mouse.move(1100, 360); await p.mouse.down(); await p.waitForTimeout(1200); await p.mouse.up();
await shot('p2_spud');
await p.keyboard.press('Digit3'); await p.waitForTimeout(200);
await p.mouse.move(900, 300); await p.mouse.down(); await p.waitForTimeout(500); await shot('p3_windup'); await p.mouse.up(); await p.waitForTimeout(400);
await shot('p4_thrown');
await p.keyboard.press('Enter'); await p.waitForTimeout(3500);
await shot('p5_run_start');
await p.keyboard.press('Digit2');
for (let i = 0; i < 8; i++) {
  await p.keyboard.down(i % 2 ? 'KeyA' : 'KeyD'); await p.mouse.move(640 + (i % 3 - 1) * 400, 200 + (i % 2) * 300); await p.mouse.down();
  await p.waitForTimeout(900); await p.mouse.up(); await p.keyboard.up(i % 2 ? 'KeyA' : 'KeyD');
}
await shot('p6_fight');
await p.keyboard.press('KeyV'); await p.waitForTimeout(800); await shot('p7_fp');
await p.keyboard.press('KeyV'); await p.waitForTimeout(300);
await p.keyboard.press('KeyR'); await p.waitForTimeout(8000); await shot('p8_restart');
console.log(logs.filter(l => /FIGHT|error|ERROR|pageerror/.test(l)).slice(-40).join('\n'));
await b.close(); process.exit(0);
