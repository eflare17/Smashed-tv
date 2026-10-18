// Headless check of sprite-maker.html's Blocks card on a phone (390 x 844, touch), with a test character made from
// Juicy Jared's sprites (godot/assets/CHARS/juicy/sprites; $CHAR=goth for Gothica's): opens it as a downloaded .json, makes the blocks,
// screenshots the 3D preview from four sides (and walking, attacking), paints with the block painter, screenshots it
// and downloads the game JSON.
//
//   node tools/test/sprite_blocks_shots.js [out dir]      (default godot/integration/voxel_shots)
//
// Needs Playwright (the cloud has it in /opt/node-tools) and Chromium (/opt/pw-browsers/chromium). The page is
// served from the repo by a little server here. The download goes to <out dir>/../sprite_maker_test.json unless
// $JSON_OUT says otherwise; tools/add_godot_character.py takes it from there.
const http = require('http'), fs = require('fs'), path = require('path');
let pw; try { pw = require('playwright'); } catch (_) { pw = require('/opt/node-tools/node_modules/playwright'); }
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.resolve(process.argv[2] || path.join(ROOT, 'godot', 'integration', 'voxel_shots'));
const JSON_OUT = process.env.JSON_OUT || path.join(require('os').tmpdir(), 'jared_blocks.json');

function testChar() {
  const d = path.join(ROOT, 'godot', 'assets', 'CHARS', process.env.CHAR || 'juicy', 'sprites'), sprites = {};
  for (const f of fs.readdirSync(d).sort()) {
    const k = f.replace(/\.png$/, ''), u = 'data:image/png;base64,' + fs.readFileSync(path.join(d, f)).toString('base64');
    const m = k.match(/^(.*)_(\d)$/);
    if (m) (sprites[m[1]] = sprites[m[1]] || []).push(u); else sprites[k] = u;
  }
  return { id: 'jared_blocks', name: 'Jared Blocks', made: '2026-10-18', tool: 'sprite-maker', sprites };
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const charFile = path.join(require('os').tmpdir(), 'jared_blocks_in.json');
  fs.writeFileSync(charFile, JSON.stringify(testChar()));
  const types = { '.html': 'text/html', '.js': 'text/javascript', '.png': 'image/png', '.json': 'application/json' };
  const srv = http.createServer((q, r) => {
    const p = path.join(ROOT, decodeURIComponent(q.url.split('?')[0]));
    if (!p.startsWith(ROOT) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { r.writeHead(404); r.end(); return; }
    r.writeHead(200, { 'Content-Type': types[path.extname(p)] || 'application/octet-stream' }); fs.createReadStream(p).pipe(r);
  }).listen(0);
  const port = srv.address().port;
  const b = await pw.chromium.launch({ executablePath: fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined,
    args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, acceptDownloads: true });
  const pg = await ctx.newPage();
  const errs = [];
  pg.on('pageerror', e => errs.push('page error: ' + e.message));
  await pg.goto('http://localhost:' + port + '/tools/sprite-maker.html');
  await pg.waitForTimeout(500);
  await pg.setInputFiles('#openFile', charFile);
  await pg.waitForFunction(() => S.sheets.standing.frames && S.sheets.standing.frames.length === 5, null, { timeout: 30000 });
  await pg.click('#bkMake');
  await pg.waitForFunction(() => BlocksUI.model && /blocks/.test(document.getElementById('bkPill').textContent), null, { timeout: 120000 });
  console.log(await pg.textContent('#bkState'), '|', await pg.textContent('#bkPill'));

  // the preview from four sides, then walking and attacking (the bottom bar hidden so it doesn't cover it)
  await pg.addStyleTag({ content: '.bar{display:none!important}' });
  const gl = await pg.$('#bkGl');
  await gl.scrollIntoViewIfNeeded();
  for (const [name, yaw, pitch] of [['front', 0, 0.12], ['side', Math.PI / 2, 0.12], ['back', Math.PI, 0.12], ['diag', -Math.PI / 4, 0.35]]) {
    await pg.evaluate(([y, p]) => BlocksUI.shot(y, p, 'stand', 0), [yaw, pitch]);
    await gl.screenshot({ path: path.join(OUT, 'sprite_maker_' + name + '.png') });
  }
  await pg.evaluate(() => BlocksUI.shot(0.6, 0.15, 'walk', 0.35));
  await gl.screenshot({ path: path.join(OUT, 'sprite_maker_walk.png') });
  await pg.evaluate(() => BlocksUI.shot(0.9, 0.15, 'attack', 0.3));
  await gl.screenshot({ path: path.join(OUT, 'sprite_maker_attack.png') });
  await pg.evaluate(() => { BlocksUI.frozen = false; BlocksUI.spin = true; BlocksUI.setAnim('walk'); });
  await pg.addStyleTag({ content: '.bar{display:flex!important}' });

  // the painter: paint the head's front a stroke of colour with a finger, check the undo, mirror and the mesh
  await pg.evaluate(() => { BlocksUI.selectPart('head'); BlocksUI.setTool('paint'); BlocksUI.colour = 0xff3fa0; });
  const grid = await pg.$('#bkGrid');
  await grid.scrollIntoViewIfNeeded();
  const bb = await grid.boundingBox();
  const count = () => pg.evaluate(() => { let n = 0; for (const c of BlocksUI.model.parts.head.values()) if (c === 0xff3fa0) n++; return n; });
  await pg.touchscreen.tap(bb.x + bb.width * 0.3, bb.y + bb.height * 0.3);
  const painted = await count();
  console.log('painted blocks (with the mirror):', painted);
  await pg.click('#bkUndo');
  console.log('after undo:', await count());
  await pg.click('#bkRedo');
  await pg.evaluate(() => document.getElementById('bkPart').scrollIntoView({ block: 'start' }));
  await pg.waitForTimeout(300);
  await pg.screenshot({ path: path.join(OUT, 'sprite_maker_painter_phone.png') });
  await pg.evaluate(() => document.getElementById('blocks').scrollIntoView({ block: 'start' }));
  await pg.waitForTimeout(400);
  await pg.screenshot({ path: path.join(OUT, 'sprite_maker_card_phone.png') });
  await pg.evaluate(() => { BlocksUI.colour = 0xff3fa0; });
  await pg.click('#bkUndo');

  const [dl] = await Promise.all([pg.waitForEvent('download'), pg.evaluate(() => { window.confirm = () => true; document.getElementById('export').click(); })]);
  await dl.saveAs(JSON_OUT);
  const j = JSON.parse(fs.readFileSync(JSON_OUT, 'utf8'));
  console.log('download:', JSON_OUT, Object.keys(j.sprites).length, 'poses,', j.voxel ? Object.keys(j.voxel.files).length + ' .vox files' : 'no blocks');
  console.log(errs.join('\n') || 'no page errors');
  await b.close(); srv.close();
  process.exit(errs.length || !j.voxel || !painted ? 1 : 0);
})();
