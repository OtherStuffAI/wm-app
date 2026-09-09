import 'dart:convert';

/// The secret remains in a top-frame closure. Cross-origin frames can see the
/// platform channel but cannot authorize calls or receive its responses.
String towerFipsBridgeScript(String documentToken, String pageOrigin) => '''
(() => {
  if (window !== window.top || location.origin !== ${jsonEncode(pageOrigin)}) return;
  const token = ${jsonEncode(documentToken)};
  let seq = 0, pair = null, revoked = false;
  const activeStreams = new Set();
  const pending = new Map();
  const workerPorts = new WeakMap();
  const portCleanups = new Set();
  const rpc = (method, params = {}) => new Promise((resolve, reject) => {
    if (revoked) { reject(new Error('Tower pairing revoked.')); return; }
    const id = String(++seq);
    const timer = (method === 'pull' || method === 'connect') ? null : setTimeout(() => { pending.delete(id); reject(new Error('Tower FIPS request timed out.')); }, 30000);
    pending.set(id, {resolve, reject, timer});
    WingmanTower.postMessage(JSON.stringify({token, id, method, params}));
  });
  window.__wingmanTowerReply = (secret, id, result, error) => {
    if (secret !== token) return;
    const p = pending.get(id);
    if (!p) return;
    pending.delete(id);
    clearTimeout(p.timer);
    if (error) p.reject(new Error(error)); else p.resolve(result);
  };
  window.__wingmanTowerRevoke = secret => {
    if (secret !== token) return;
    revoked = true; pair = null;
    for (const stop of [...activeStreams]) stop();
    for (const cleanup of [...portCleanups]) cleanup();
    for (const p of pending.values()) { clearTimeout(p.timer); p.reject(new Error('Tower pairing revoked.')); }
    pending.clear();
  };
  const encode = bytes => {
    let s = ''; for (const b of bytes) s += String.fromCharCode(b);
    return btoa(s);
  };
  const decode = s => Uint8Array.from(atob(s), c => c.charCodeAt(0));
  const nativeFetch = async (input, init = {}) => {
    if (!pair) throw new Error('Connect to a paired Tower first.');
    const request = new Request(input, init);
    if (!request.url.startsWith(pair.endpoint + '/'))
      throw new Error('Request must target the paired Tower.');
    if (request.signal.aborted) throw request.signal.reason || new DOMException('Aborted', 'AbortError');
    const headers = Object.fromEntries(request.headers.entries());
    // Native transport must deliver compressed representation consistently.
    // A page cannot set accept-encoding; native backend handles decompression.
    const opening = rpc('open', {url: request.url, method: request.method, headers});
    let earlyAbort, id;
    const interrupted = new Promise((_, reject) => {
      earlyAbort = () => reject(request.signal.reason || new DOMException('Aborted', 'AbortError'));
      request.signal.addEventListener('abort', earlyAbort, {once:true});
      if (request.signal.aborted) earlyAbort();
    });
    try { id = await Promise.race([opening, interrupted]); }
    catch (e) {
      opening.then(requestId => rpc('cancel', {requestId})).catch(() => {});
      throw e;
    } finally { request.signal.removeEventListener('abort', earlyAbort); }
    let cancelled = false, responseController, uploadReader;
    const cancel = () => {
      if (cancelled) return;
      cancelled = true;
      activeStreams.delete(stop);
      rpc('cancel', {requestId: id}).catch(() => {});
      request.signal.removeEventListener('abort', abort);
    };
    const stop = () => { cancel(); responseController?.error(new Error('Tower pairing revoked.')); };
    activeStreams.add(stop);
    const abort = () => {
      cancel();
      uploadReader?.cancel().catch(() => {});
      if (responseController) responseController.error(request.signal.reason || new DOMException('Aborted', 'AbortError'));
    };
    request.signal.addEventListener('abort', abort, {once:true});
    if (request.signal.aborted) abort();
    try {
      if (request.body) {
        const reader = request.body.getReader();
        uploadReader = reader;
        try {
          while (true) {
            const {done, value} = await reader.read();
            if (done) break;
            for (let offset = 0; offset < value.length; offset += 65536) {
              if (cancelled) throw new DOMException('Aborted', 'AbortError');
              await rpc('write', {requestId:id, chunk:encode(value.subarray(offset, offset+65536))});
            }
          }
        } finally { await reader.cancel().catch(() => {}); uploadReader = null; }
      }
      if (cancelled) throw new DOMException('Aborted', 'AbortError');
      const meta = await rpc('finish', {requestId:id});
      if (cancelled) throw new DOMException('Aborted', 'AbortError');
      const empty = request.method === 'HEAD' || [204,205,304].includes(meta.status);
      const body = empty ? null : new ReadableStream({
        start(controller) { responseController = controller; },
        async pull(controller) {
          try {
            const next = await rpc('pull', {requestId:id});
            if (cancelled) return;
            if (next.done) {
              activeStreams.delete(stop);
              request.signal.removeEventListener('abort', abort);
              controller.close();
            } else controller.enqueue(decode(next.chunk));
          } catch (e) { if (!cancelled) { controller.error(e); cancel(); } }
        },
        cancel,
      }, {highWaterMark:0});
      if (empty) cancel();
      return new Response(body, meta);
    } catch (e) { cancel(); if (request.signal.aborted) throw request.signal.reason || new DOMException('Aborted','AbortError'); throw e; }
  };
  Object.defineProperty(window, 'wingmanTowerTransport', {configurable:true, value:Object.freeze({
    version:2, available:true,
    async connect(options) {
      pair = await rpc('connect', options);
      return pair;
    },
    fetch:nativeFetch,
    detachWorker(worker) { workerPorts.get(worker)?.(); workerPorts.delete(worker); },
    attachWorker(worker) {
      workerPorts.get(worker)?.();
      const channel = new MessageChannel();
      const requests = new Map();
      const cleanup = (close = true) => {
        for (const [id,state] of requests) {
          state.abort.abort(); channel.port1.postMessage({type:'error',id});
        }
        requests.clear();
        if (close) { channel.port1.close(); portCleanups.delete(cleanup); }
      };
      workerPorts.set(worker,cleanup); portCleanups.add(cleanup);
      const send = value => channel.port1.postMessage(value);
      channel.port1.onmessage = async ({data}) => {
        const id = data?.id;
        if (typeof id !== 'string') return;
        try {
          if (data.type === 'request') {
            if (data.bodyBase64 != null && (typeof data.bodyBase64 !== 'string' || data.bodyBase64.length > 22369624)) throw new Error('Worker upload exceeds 16 MiB');
            if (requests.has(id) || requests.size >= 64) throw new Error('Duplicate or excessive request');
            const state = {abort:new AbortController(), reader:null, busy:false};
            requests.set(id,state);
            const body = data.bodyBase64 == null ? undefined : decode(data.bodyBase64);
            if (body && body.byteLength > 16777216) throw new Error('Worker upload exceeds 16 MiB');
            const response = await nativeFetch(data.url, {
              method:data.method, headers:data.headers,
              body,
              signal:state.abort.signal,
            });
            if (requests.get(id) !== state) { await response.body?.cancel(); return; }
            state.reader = response.body?.getReader();
            send({type:'headers',id,status:response.status,headers:[...response.headers]});
          } else if (data.type === 'cancel') {
            const state = requests.get(id); requests.delete(id);
            state?.abort.abort(); await state?.reader?.cancel().catch(()=>{});
          } else if (data.type === 'pull') {
            const state = requests.get(id);
            if (!state || state.busy) return;
            state.busy = true;
            const next = await state.reader?.read() || {done:true};
            state.busy = false;
            if (requests.get(id) !== state) return;
            if (next.done) { requests.delete(id); send({type:'end',id}); }
            else send({type:'chunk',id,bodyBase64:encode(next.value)});
          }
        } catch (_) {
          const state = requests.get(id); requests.delete(id);
          state?.abort.abort(); send({type:'error',id});
        }
      };
      channel.port1.start();
      worker.postMessage({type:'wingman-tower-transport-port',port:channel.port2},[channel.port2]);
    },
    async disconnect() { pair=null; for (const cleanup of [...portCleanups]) cleanup(false); await rpc('disconnect'); },
  })});
  window.dispatchEvent(new Event('wingman-tower-transport-ready'));
})();
''';
