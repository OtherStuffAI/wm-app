/** Narrow external signer for zsp v0.4.17 JSONL. No private Nostr key access. */
import { createHash, X509Certificate, verify as verifyCrypto } from "node:crypto";
import { resolve } from "node:path";

export const PACKAGE = "com.wingmanbefree.wingman_app.nightly";
export const PUBLISHER = "ffdc30446bede234446a69124bae94cdbddebf24f0abee4a5cabfc1124313c2e";
export const RELAY = "wss://relay.zapstore.dev";
export const BLOSSOM = "https://cdn.zapstore.dev";
type Event = {kind:number;pubkey:string;created_at:number;tags:string[][];content:string;id?:string;sig?:string};
export function tag(e:Event, name:string) { return e.tags.find(t=>t[0]===name)?.[1]; }
export function validate(e:Event, cert:string) {
  const allowed:Record<number,string[]>={30509:["d","signature","expiry"],32267:["d","name","summary","icon","image","repository","f","h","t","license","website"],30063:["i","version","d","c","f","e"],3063:["i","x","version","url","m","size","f","min_platform_version","target_platform_version","filename","variant","commit","supported_nip","version_code","apk_certificate_hash"]};
  if(e.tags.some(t=>!allowed[e.kind]?.includes(t[0])) || new TextEncoder().encode(e.content).length>32768) throw Error("Unexpected release tags or content size");
  const singleton=e.tags.filter(t=>!["f","t","image","e","supported_nip","url"].includes(t[0])).map(t=>t[0]);
  if(new Set(singleton).size!==singleton.length)throw Error("Duplicate identity tag");
  if(e.pubkey!==PUBLISHER || ![3063,30063,32267,30509].includes(e.kind)) throw Error("Wrong publisher or kind");
  if(e.kind===30509) {
    if(tag(e,"d")!==cert || e.content!=="" || e.tags.some(t=>!["d","signature","expiry"].includes(t[0]))) throw Error("Wrong certificate proof");
  } else {
    if(tag(e,e.kind===32267?"d":"i")!==PACKAGE) throw Error("Stable or foreign package rejected");
    if(e.kind===32267 && (tag(e,"name")!=="Wingman Nightly" || tag(e,"repository")!=="https://github.com/OtherStuffAI/wingman-nightly")) throw Error("Wrong app metadata");
    if(e.kind===30063 && (tag(e,"c")!=="nightly" || tag(e,"d")!==`${PACKAGE}@${tag(e,"version")}`)) throw Error("Wrong release channel");
    if(e.kind===3063 && (tag(e,"apk_certificate_hash")!==cert || !/^[1-9]\d*$/.test(tag(e,"version_code")??"") || !/^[a-f0-9]{64}$/.test(tag(e,"x")??""))) throw Error("Invalid asset identity");
  }
  for(const t of e.tags.filter(t=>["url","icon","image"].includes(t[0]))) if(!t[1].startsWith(BLOSSOM+"/") || !/^[a-f0-9]{64}$/.test(t[1].slice(BLOSSOM.length+1))) throw Error("Unexpected asset host or hash");
}
export async function signChecked(e:Event, cert:string, call:any, verifyEvent:any) {
  validate(e,cert);
  const {event:signed}=await call("/api/mcp/capabilities/nostr-event",{event:{kind:e.kind,content:e.content,tags:e.tags}});
  if(!verifyEvent(signed) || signed.pubkey!==PUBLISHER || signed.kind!==e.kind || signed.content!==e.content || JSON.stringify(signed.tags)!==JSON.stringify(e.tags)) throw Error("Broker mutated signing template or identity");
  if(e.kind===30509 && signed.created_at!==e.created_at) throw Error("Certificate proof timestamp changed; regenerate proof, never publish");
  return signed as Event;
}
export function verifyProof(e:Event, der:Uint8Array) {
  const certificate=new X509Certificate(der);
  const cert=createHash("sha256").update(certificate.raw).digest("hex");
  validate(e,cert);
  const message=`Verifying at ${e.created_at} until ${tag(e,"expiry")} that I control the following Nostr public key: ${PUBLISHER}`;
  if(Number(tag(e,"expiry"))<=e.created_at || !verifyCrypto("sha256",Buffer.from(message),certificate.publicKey,Buffer.from(tag(e,"signature")??"","base64"))) throw Error("Invalid Android keystore ownership proof");
}
export async function exchange(messages:any[], filter:any, publish?:Event) {
  return await new Promise<Event[]>((ok,fail)=>{
    const ws=new WebSocket(RELAY);const events:Event[]=[];const timeout=setTimeout(()=>{ws.close();fail(Error("Relay delivery/readback uncertain"));},30000);
    const done=(error?:Error)=>{clearTimeout(timeout);ws.close();error?fail(error):ok(events);};
    ws.onopen=()=>{for(const m of messages)ws.send(JSON.stringify(m));};
    ws.onerror=()=>done(Error("Relay transport failed; reconcile before retry"));
    ws.onmessage=({data})=>{const m=JSON.parse(String(data));if(m[0]==="EVENT") events.push(m[2]);if(m[0]==="EOSE")done();if(m[0]==="CLOSED")done(Error(String(m[2])));if(m[0]==="OK" && publish && m[1]===publish.id)done(m[2]?undefined:Error(`Relay rejected: ${m[3]}`));};
  });
}
async function main() {
  const [action,runText,cert]=Bun.argv.slice(2);const run=resolve(runText);
  const autopilot=resolve(process.env.AUTOPILOT_REPO??"../autopilot");
  const {callCapabilityBroker,readCapabilityIdentity}=await import(autopilot+"/src/mcp/capability-client.ts");
  const {verifyEvent}=await import(autopilot+"/node_modules/nostr-tools/lib/esm/index.js");
  if(action==="history") {
    const events=await exchange([["REQ","history",{authors:[PUBLISHER],kinds:[3063],"#i":[PACKAGE]}]],null);
    if(events.some(e=>!verifyEvent(e)||e.pubkey!==PUBLISHER||tag(e,"i")!==PACKAGE||!Number.isSafeInteger(Number(tag(e,"version_code")))||Number(tag(e,"version_code"))<1)) throw Error("Invalid relay history");
    console.log(JSON.stringify({maxVersionCode:Math.max(0,...events.map(e=>Number(tag(e,"version_code"))))}));return;
  }
  if((await readCapabilityIdentity()).botPubkeyHex!==PUBLISHER)throw Error("Rick broker identity required");
  if(action==="sign") {
    const unsigned=(await Bun.file(run+"/unsigned.jsonl").text()).trim().split("\n").map(x=>JSON.parse(x)) as Event[];
    if(unsigned.length!==3 || new Set(unsigned.map(e=>e.kind)).size!==3)throw Error("Expected exactly zsp app/release/asset");
    const asset=unsigned.find(e=>e.kind===3063)!;const release=unsigned.find(e=>e.kind===30063)!;const app=unsigned.find(e=>e.kind===32267)!;
    const signedAsset=await signChecked(asset,cert,callCapabilityBroker,verifyEvent);
    release.tags=release.tags.map(t=>t[0]==="e"?["e",signedAsset.id!,RELAY]:t);
    const signed=[signedAsset,await signChecked(release,cert,callCapabilityBroker,verifyEvent),await signChecked(app,cert,callCapabilityBroker,verifyEvent)];
    await Bun.write(run+"/signed.json",JSON.stringify(signed,null,2));return;
  }
  if(action==="proof") {
    const proof=await Bun.file(run+"/proof-unsigned.json").json();
    const signed=await signChecked(proof,cert,callCapabilityBroker,verifyEvent);
    verifyProof(signed,new Uint8Array(await Bun.file(run+"/certificate.der").arrayBuffer()));
    await Bun.write(run+"/proof-signed.json",JSON.stringify(signed));return;
  }
  if(action==="upload") {
    const {uploadBlossomObject}=await import(autopilot+"/src/mcp/blossom-client.ts");
    const events=await Bun.file(run+"/signed.json").json() as Event[];
    const objects:[[string,string,string],[string,string,string]]=[["app-release.apk",tag(events[0],"x")!,"application/vnd.android.package-archive"],["icon.png",tag(events[2],"icon")!.split("/").at(-1)!,"image/png"]];
    for(const [filename,hash,contentType] of objects){const bytes=new Uint8Array(await Bun.file(run+"/"+filename).arrayBuffer());if(createHash("sha256").update(bytes).digest("hex")!==hash)throw Error("Upload bytes changed");const receipt=await uploadBlossomObject({server:BLOSSOM,bytes,contentType});await Bun.write(run+"/"+filename+".upload.json",JSON.stringify(receipt));const response=await fetch(BLOSSOM+"/"+hash);if(!response.ok||createHash("sha256").update(new Uint8Array(await response.arrayBuffer())).digest("hex")!==hash)throw Error("Public bytes unavailable or hash mismatch");}return;
  }
  if(action==="publish" || action==="readback") {
    const events=[await Bun.file(run+"/proof-signed.json").json(),...await Bun.file(run+"/signed.json").json()] as Event[];
    for(const e of events){validate(e,cert);if(!verifyEvent(e))throw Error("Signature failed");if(action==="publish")await exchange([["EVENT",e]],null,e);}
    const ids=events.map(e=>e.id);const found=await exchange([["REQ","readback",{ids}]],null);
    if(ids.some(id=>!found.some(e=>e.id===id&&verifyEvent(e))))throw Error("Published event readback incomplete");
    await Bun.write(run+"/relay-readback.json",JSON.stringify(found,null,2));console.log(JSON.stringify({accepted:ids,listing:`https://zapstore.dev/apps/${PACKAGE}`}));return;
  }
  throw Error("Unknown action");
}
if(import.meta.main)main().catch(e=>{console.error(e.message);process.exitCode=1;});
