import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import test from 'node:test';

// Execute the production injected script with a synthetic native RPC channel.
const source = readFileSync(new URL('../../app/lib/src/features/browser/grasp_fips_bridge_script.dart', import.meta.url), 'utf8')
  .split("=> '''\n")[1].split("\n''';")[0]
  .replace('${jsonEncode(pageOrigin)}', JSON.stringify('https://example.com'))
  .replace('${jsonEncode(documentToken)}', JSON.stringify('test-token'));
function host({ frame = false, origin = 'https://example.com' } = {}) {
  const window = new EventTarget();
  window.top = frame ? {} : window;
  window.nostr = { signEvent() { throw Error('Unexpected signing'); } };
  const calls = [];
  const endpoint = 'http://synthetic.fips:8787';
  let downloaded = false;
  const context = {
    window, location: { origin }, EventTarget, Event, MessageEvent,
    Request, Response, ReadableStream, AbortController, DOMException,
    Blob, URL, TextEncoder, Uint8Array, ArrayBuffer, MessageChannel,
    setTimeout, clearTimeout, atob, btoa,
    WingmanGrasp: { postMessage(message) {
      const call = JSON.parse(message); calls.push(call);
      let result;
      if (call.method === 'connect') result = { version: 1, endpoint };
      if (call.method === 'open') result = 'request';
      if (call.method === 'finish') result = { status: 201, headers: { 'Content-Type': 'application/octet-stream' } };
      if (call.method === 'pull') {
        result = downloaded ? { done: true } : { done: false, chunk: btoa('\x00\xff\x0d') };
        downloaded = true;
      }
      queueMicrotask(() => window.__wingmanGraspReply('test-token', call.id, result));
    } },
  };
  return { window, calls, endpoint, run: () => runInNewContext(source, context) };
}

test('both names share the frozen capability before readiness, without changing the signer', async () => {
  const h = host(); const signer = h.window.nostr;
  let ready = 0;
  h.window.addEventListener('wingman-grasp-transport-ready', () => {
    ready++;
    assert.equal(h.window.fipsTransport, h.window.wingmanGraspTransport);
    assert.ok(Object.isFrozen(h.window.fipsTransport));
  });
  h.run();
  assert.equal(ready, 1); assert.equal(h.window.nostr, signer);
  await h.window.fipsTransport.connect({ endpoint: h.endpoint });
  const response = await h.window.wingmanGraspTransport.fetch(h.endpoint + '/echo', {
    method: 'POST', body: new Uint8Array([0, 255, 13]),
  });
  assert.equal(response.status, 201);
  assert.deepEqual([...new Uint8Array(await response.arrayBuffer())], [0, 255, 13]);
  assert.equal(h.calls.find(c => c.method === 'write').params.chunk, 'AP8N');
  await h.window.fipsTransport.disconnect();
  await assert.rejects(h.window.wingmanGraspTransport.fetch(h.endpoint + '/'), /Connect/);
  await h.window.wingmanGraspTransport.connect({ endpoint: h.endpoint });
  h.window.__wingmanGraspRevoke('test-token');
  await assert.rejects(h.window.fipsTransport.connect({ endpoint: h.endpoint }), /revoked/);
  await assert.rejects(h.window.wingmanGraspTransport.connect({ endpoint: h.endpoint }), /revoked/);
});

for (const options of [{ frame: true }, { origin: 'https://other.example' }]) {
  test(`does not install either capability outside approved top origin: ${JSON.stringify(options)}`, () => {
    const h = host(options); h.run();
    assert.equal(h.window.fipsTransport, undefined);
    assert.equal(h.window.wingmanGraspTransport, undefined);
    assert.equal(h.calls.length, 0);
  });
}
