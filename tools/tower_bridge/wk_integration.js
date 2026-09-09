(async()=> {
  const assert = (ok,label) => { if(!ok) throw new Error(label); };
  const endpoint='http://npub1qmc3cvfz0yu2hx96nq3gp55zdan2qclealn7xshgr448d3nh6lks7zel98.fips:8787';
  try {
    const frame=document.createElement('iframe');
    frame.srcdoc='<script>window.webkit.messageHandlers.WingmanTower.postMessage("forged-frame");<\/script>';
    document.body.append(frame);
    await new Promise(resolve=>setTimeout(resolve,150));
    const bridge=window.wingmanTowerTransport;
    assert(location.origin==='https://example.com' && isSecureContext,'HTTPS origin preserved');
    const pair=await bridge.connect({endpoint,logicalTower:'https://tower.example'});
    assert(pair.version===2 && pair.transport==='native' && !pair.proxyBaseUrl,'v2 descriptor');
    let rejected=false;
    try {await bridge.fetch('https://tower.example/public');}catch(_){rejected=true;}
    assert(rejected,'public target rejected');
    const bytes=Uint8Array.from({length:180000},(_,i)=>i%256);
    const response=await bridge.fetch(endpoint+'/upload?encoded=%2F',{
      method:'POST',headers:{authorization:'Nostr signed-mesh-target','content-type':'application/octet-stream'},body:bytes});
    assert(response.status===201,'status');
    assert(response.headers.get('content-disposition').includes('bytes.bin'),'content headers');
    const echoed=new Uint8Array(await response.arrayBuffer());
    assert(echoed.length===bytes.length && echoed.every((b,i)=>b===bytes[i]),'binary upload/download');
    const redirect=await bridge.fetch(endpoint+'/redirect');assert(redirect.status===502,'redirect blocked');
    await redirect.body.cancel();
    const already=new AbortController(); already.abort(new DOMException('test timeout','TimeoutError'));
    let alreadyReason=false;try{await bridge.fetch(endpoint+'/never',{signal:already.signal});}catch(e){alreadyReason=e.name==='TimeoutError';}
    assert(alreadyReason,'pre-aborted TimeoutError');
    const early=new AbortController(); const started=performance.now();
    const opening=bridge.fetch(endpoint+'/slow-open',{signal:early.signal});
    setTimeout(()=>early.abort(),10);
    let earlyAborted=false;try{await opening;}catch(e){earlyAborted=e.name==='AbortError';}
    assert(earlyAborted && performance.now()-started<350,'abort while open pending');
    const abort=new AbortController();
    const hanging=bridge.fetch(endpoint+'/hang',{signal:abort.signal});
    setTimeout(()=>abort.abort(),100);
    let aborted=false;try {await hanging;}catch(e){aborted=e.name==='AbortError';}
    assert(aborted,'preheaders abort');
    const afterHeaders=new AbortController();
    const stream=await bridge.fetch(endpoint+'/events',{signal:afterHeaders.signal});
    const reader=stream.body.getReader();let text='';const decoder=new TextDecoder();
    while(!text.includes('\n\n')){const next=await reader.read();text+=decoder.decode(next.value,{stream:true});}
    assert(text.includes('café'),'split UTF8 SSE before EOF');
    afterHeaders.abort(new DOMException('test timeout','TimeoutError'));
    let timeoutPreserved=false;try{await reader.read();}catch(e){timeoutPreserved=e.name==='TimeoutError';}
    assert(timeoutPreserved,'TimeoutError after headers');
    const source=`onmessage=({data})=>{if(data.type!=='wingman-tower-transport-port')return;
      const p=data.port;let text='';p.onmessage=({data:d})=>{
        if(d.type==='headers'){if(d.status!==200)throw Error('worker status');p.postMessage({type:'pull',id:'sse'});}
        if(d.type==='chunk'){text+=atob(d.bodyBase64);if(text.includes('\\n\\n')){p.postMessage({type:'cancel',id:'sse'});postMessage('worker SSE streamed');}else p.postMessage({type:'pull',id:'sse'});}
        if(d.type==='error')postMessage('FAIL worker');};p.start();
      p.postMessage({type:'request',id:'sse',url:${JSON.stringify(endpoint+'/events')},method:'GET',headers:[],bodyBase64:null});};`;
    const worker=new Worker(URL.createObjectURL(new Blob([source],{type:'text/javascript'})));
    const done=new Promise(resolve=>worker.onmessage=({data})=>resolve(data));
    bridge.attachWorker(worker);
    assert(await done==='worker SSE streamed','worker port/SSE');worker.terminate();
    await bridge.disconnect();
    window.webkit.messageHandlers.Result.postMessage('PASS HTTPS WKWebView native v2: binary 180KB, auth/status/headers, target/redirect rejection, preheaders abort, split UTF8 SSE, worker port streaming/cancel');
  }catch(e){window.webkit.messageHandlers.Result.postMessage('FAIL '+e.name+': '+e.message);}
})();
