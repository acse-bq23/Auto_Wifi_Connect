import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

function loadDotEnv(file) {
  try {
    if (!fs.existsSync(file)) return;
    const content = fs.readFileSync(file, 'utf8');
    for (const line of content.split(/\r?\n/)) {
      if (!line || line.trim().startsWith('#')) continue;
      const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
      if (!m) continue;
      const key = m[1];
      const val = m[2].replace(/^['"]|['"]$/g, '');
      if (process.env[key] === undefined) process.env[key] = val;
    }
  } catch {}
}

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJ = process.env.AUTO_WIFI_PROJ || __dirname;
const ENV_PATH = process.env.AUTO_WIFI_ENV || path.join(PROJ, '.env');
loadDotEnv(ENV_PATH);
const LOGIN_CANDIDATES = (() => {
  const envList = process.env.PORTAL_LOGIN_CANDIDATES;
  if (envList) {
    return envList.split(',').map(s => s.trim()).filter(Boolean);
  }
  // 示例占位，需按实际门户地址覆盖
  return [
    'http://portal.example.com/',
    'http://portal.example.com/login',
    'http://portal.example.com/quick'
  ];
})();

const ACCOUNT = process.env.PORTAL_ACCOUNT || '';
const PASSWORD = process.env.PORTAL_PASSWORD || '';

function log(msg) {
  const ts = new Date().toLocaleString('zh-CN', { hour12: false });
  console.log(`${ts} ${msg}`);
}
async function dump(page, tag) {
  try {
    const ts = Date.now();
    await page.screenshot({ path: path.join(PROJ, `debug-${tag}-${ts}.png`), fullPage: true });
    fs.writeFileSync(path.join(PROJ, `debug-${tag}-${ts}.html`), await page.content());
  } catch {}
}

// —— 多探针联网校验：任一成功即认为已联外网 ——
async function internetOK(ctx) {
  const probes = [
    { url: 'http://neverssl.com/',               type: 'status',  ok: s => /^200|30[12]$/.test(String(s)) },
    { url: 'http://www.msftconnecttest.com/connecttest.txt', type: 'body',    ok: b => /Microsoft Connect Test/i.test(b) },
    { url: 'http://captive.apple.com/hotspot-detect.html',   type: 'body',    ok: b => /Success/i.test(b) },
    { url: 'https://www.qq.com',                 type: 'status',  ok: s => /^200|30[12]$/.test(String(s)) },
    { url: 'https://www.baidu.com',              type: 'status',  ok: s => /^200|30[12]$/.test(String(s)) },
  ];
  for (const p of probes) {
    try {
      const page = await ctx.newPage();
      const resp = await page.goto(p.url, { timeout: 8000, waitUntil: 'domcontentloaded' });
      if (resp) {
        if (p.type === 'status') {
          const s = resp.status();
          await page.close();
          if (p.ok(s)) return true;
        } else {
          const body = await page.content();
          await page.close();
          if (p.ok(body)) return true;
        }
      } else {
        await page.close();
      }
    } catch {
      // 忽略错误，换下一个探针
    }
  }
  return false;
}

async function selectRoot(page) {
  for (const f of page.frames()) {
    try {
      if (
        (await f.getByText(/登.?录|账号|扫码|退出|成功登录/).first().count()) > 0 ||
        (await f.locator('input').count()) > 0
      ) return f;
    } catch {}
  }
  return page;
}

async function waitLoginForm(root, ms=8000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const hasUser = await root.getByRole('textbox', { name: /账号|用户名|手机|工号/ }).first().isVisible().catch(()=>false)
                || await root.locator('input[name="username"]:visible').first().isVisible().catch(()=>false)
                || await root.locator('input[type="text"]:visible').first().isVisible().catch(()=>false);
    const hasPwd  = await root.locator('#quick_password:visible').first().isVisible().catch(()=>false)
                || await root.locator('input[name="pwd"]:visible').first().isVisible().catch(()=>false)
                || await root.locator('input[type="password"]:visible').first().isVisible().catch(()=>false);
    if (hasUser || hasPwd) return true;
    await root.waitForTimeout(300);
  }
  return false;
}

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const ctx = await browser.newContext();
  const page = await ctx.newPage();

  try {
    if (!ACCOUNT || !PASSWORD) {
      log('missing account or password, please set PORTAL_ACCOUNT / PORTAL_PASSWORD or edit portal-login.mjs');
      await browser.close(); process.exit(1);
    }
    log('open candidates...');
    let root = page;

    for (const url of LOGIN_CANDIDATES) {
      log('goto ' + url);
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 20000 });
      root = await selectRoot(page);

      // 如果是“已成功登录”页：先尝试直接判定在线；若不在线，则点击“退出”再重登
      const successVisible = await root.getByText(/成功登录/).first().isVisible().catch(()=>false);
      if (successVisible) {
        if (await internetOK(ctx)) {
          log('already logged in, internet reachable.');
          await browser.close(); process.exit(0);
        } else {
          log('logged-in page but internet not reachable, logout then re-login...');
          const quitBtn = root.locator('input.btn_quit[value="退出"]');
          if (await quitBtn.isVisible().catch(()=>false)) {
            await Promise.all([ page.waitForLoadState('domcontentloaded').catch(()=>{}), quitBtn.click().catch(()=>{}) ]);
          } else {
            try { await page.goto('http://114.114.114.114:90/logout', { timeout: 5000 }); } catch {}
          }
          await page.waitForTimeout(1000);
        }
      }

      // 尝试找到登录表单
      root = await selectRoot(page);
      const okForm = await waitLoginForm(root, 8000);
      if (okForm) break;
    }

    // —— 填账号 ——
    let userFilled = false;
    for (const loc of [
      root.getByRole('textbox', { name: /账号|用户名|手机|工号/ }).first(),
      root.locator('input[name="username"]:visible').first(),
      root.locator('input[type="text"]:visible').first()
    ]) {
      if (await loc.isVisible().catch(()=>false)) {
        await loc.click().catch(()=>{});
        await loc.fill(ACCOUNT, { timeout: 5000 });
        userFilled = true; break;
      }
    }
    if (!userFilled) {
      await root.locator('input').evaluateAll((els, v) => {
        for (const el of els) {
          const n = (el.getAttribute('name')||'').toLowerCase();
          if (n.includes('user') || n.includes('name') || n.includes('account') || n.includes('login')) {
            el.value = v; el.dispatchEvent(new Event('input', { bubbles: true }));
          }
        }
      }, ACCOUNT);
    }

    // —— 填密码 ——
    let pwdFilled = false;
    for (const loc of [
      root.locator('#quick_password:visible').first(),
      root.locator('input[name="pwd"]:visible').first(),
      root.locator('input[type="password"]:visible').first()
    ]) {
      if (await loc.isVisible().catch(()=>false)) {
        await loc.click().catch(()=>{});
        await loc.fill(PASSWORD, { timeout: 8000 });
        pwdFilled = true; break;
      }
    }
    if (!pwdFilled) {
      await root.locator('input').evaluateAll((els, v) => {
        for (const el of els) {
          const n = (el.getAttribute('name')||'').toLowerCase();
          if (el.getAttribute('type') === 'password' || n === 'pwd') {
            el.value = v;
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
          }
        }
      }, PASSWORD);
    }

    // 勾选“记住账号密码”（如果有）
    const remember = root.getByRole('checkbox', { name: /记住|保存/i });
    if (await remember.isVisible().catch(()=>false)) await remember.check({ force: true }).catch(()=>{});

    // —— 点击登录 ——
    const btns = [
      root.getByRole('button', { name: /登.?录/ }).first(),
      root.locator('button:has-text("登录"), button:has-text("登 录")').first(),
      root.getByText(/登.?录/).locator('xpath=ancestor-or-self::button[1]').first()
    ];
    let clicked = false;
    for (const b of btns) {
      if (await b.isVisible().catch(()=>false)) {
        await Promise.all([ root.waitForLoadState('networkidle').catch(()=>{}), b.click({ timeout: 8000 }) ]);
        clicked = true; break;
      }
    }
    if (!clicked) { await dump(root, 'no-login-button'); throw new Error('login button not found/visible'); }

    // —— 登录后：成功文案 或 多探针之一成功 即判定成功 ——
    const successAfter = await root.getByText(/成功登录/).first().isVisible().catch(()=>false);
    if (successAfter || await internetOK(ctx)) {
      log('portal login OK / internet reachable.');
      await browser.close(); process.exit(0);
    } else {
      await dump(root, 'after-login-no-inet');
      log('login finished but internet not reachable (all probes failed).');
      await browser.close(); process.exit(2);
    }
  } catch (e) {
    log('error: ' + (e?.message || e));
    await dump(page, 'exception');
    await browser.close(); process.exit(1);
  }
})();
