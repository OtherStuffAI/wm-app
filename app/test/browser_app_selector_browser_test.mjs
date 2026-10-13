// Run after the Flutter fixture test; see docs/app-selector-validation.md.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
const directory = process.argv[2];
if (!directory) throw new Error('Pass the ignored evidence directory containing selector.html and discovery.js.');
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const browser = await chromium.launch({headless:true, ...(process.env.CHROMIUM_EXECUTABLE ? {executablePath:process.env.CHROMIUM_EXECUTABLE}: {})});
try {
  const html = await readFile(join(directory, 'selector.html'), 'utf8');
  const discovery = await readFile(join(directory, 'discovery.js'), 'utf8');
  for (const width of [320,390,768,1440]) {
    const page = await browser.newPage({viewport:{width,height:900}});
    await page.route('**/*', route => route.fulfill({status:404,body:''}));
    await page.setContent(html);
    await page.evaluate(() => {window.calls=[];window.WingmanSigner={postMessage:raw=>window.calls.push(JSON.parse(raw))};});
    await page.waitForFunction(() => Array.from(document.querySelectorAll('.icon img')).every(img=>img.complete));
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true, `No horizontal overflow at ${width}px`);
    assert.equal(await page.locator('.edit:visible').count(),0);
    assert.equal(await page.locator('.remove:visible').count(),0);
    assert.equal(await page.locator('.icon img').count(),1,'Custom image survives; broken favicon falls back to initial');
    const launch = page.locator('.app-open').filter({hasText:'Solvitur Ambulando'});
    await launch.click();
    assert.equal((await page.evaluate(()=>window.calls.at(-1))).params.url,'https://apps.example/deck?workspace=deliberately-long-route&scope=keep-this#today');
    await page.screenshot({path:join(directory,`selector-${width}.png`),fullPage:true});
    await page.getByRole('button',{name:'Edit apps and background'}).click();
    assert.equal(await page.locator('.edit:visible').count(),5);
    assert.equal(await page.locator('.remove:visible').count(),5);
    await page.getByRole('button',{name:'Edit Solvitur Ambulando',exact:true}).click();
    assert.equal((await page.evaluate(()=>window.calls.at(-1))).method,'editBookmark');
    await page.getByRole('button',{name:'Remove Solvitur Ambulando',exact:true}).click();
    assert.equal((await page.evaluate(()=>window.calls.at(-1))).method,'removeBookmark');
    await page.getByRole('button',{name:'Choose background'}).click();
    assert.equal((await page.evaluate(()=>window.calls.at(-1))).method,'chooseBackground');
    await page.screenshot({path:join(directory,`selector-edit-${width}.png`),fullPage:true});
    await page.close();
  }
  async function discover({host='apps.example',manifest={icons:[{src:'./small.png',sizes:'32x32'},{src:'./large.png',sizes:'192x192'}]},length,manifestHref='/metadata/app.webmanifest'}) {
    const page = await browser.newPage();
    const requests=[];
    await page.route('**/*',async route=>{
      const request=route.request(); requests.push({url:request.url(),headers:request.headers()});
      if(request.url().includes('/metadata/')) await route.fulfill({status:200,contentType:'application/manifest+json',headers:length?{'content-length':String(length)}:{},body:typeof manifest==='string'?manifest:JSON.stringify(manifest)});
      else await route.fulfill({status:200,contentType:'text/html',body:`<link rel="icon" href="/favicon.png"><link rel="manifest" href="${manifestHref}">`});
    });
    await page.goto(`https://${host}/deep/app?keep=1#part`);
    await page.evaluate(()=>{window.calls=[];window.WingmanSigner={postMessage:raw=>window.calls.push(JSON.parse(raw))};document.cookie='secret=must-not-send';});
    await page.addScriptTag({content:discovery});
    await page.waitForTimeout(150);
    const calls = await page.evaluate(()=>window.calls);
    await page.close();
    return {calls,requests};
  }
  const valid=await discover({});
  assert.equal(valid.calls[0].params.iconUrl,'https://apps.example/favicon.png');
  assert.equal(valid.calls.at(-1).params.iconUrl,'https://apps.example/metadata/large.png');
  assert.equal(valid.calls.at(-1).params.url,'https://apps.example/deep/app?keep=1#part');
  assert.equal(valid.requests.find(r=>r.url.includes('/metadata/')).headers.cookie,undefined,'Manifest omits credentials');
  assert.equal((await discover({manifest:'broken JSON'})).calls.length,1,'Malformed manifest retains favicon');
  assert.equal((await discover({length:131073})).calls.length,1,'Oversized manifest retains favicon');
  assert.equal((await discover({manifest:{icons:[{src:'https://other.example/icon.png'},{src:'http://peer.fips/icon.png'},{src:'javascript:alert(1)'}]}})).calls.length,1,'Cross-origin/service/script metadata rejected');
  const cross=await discover({manifestHref:'https://other.example/manifest'});
  assert.equal(cross.requests.filter(r=>new URL(r.url).hostname==='other.example').length,0,'Cross-origin manifest never fetched by discovery');
  assert.equal((await discover({host:'peer.fips'})).calls.length,0,'FIPS page cannot trigger metadata fetching');
  console.log('Passed: responsive tiles, exact launch URL, edit/delete/background controls, custom-image precedence, fallback, manifest resolution, credentials omission and failure/security cases.');
} finally { await browser.close(); }
