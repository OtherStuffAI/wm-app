import { test, expect } from "bun:test";
import { validate, signChecked, verifyProof, PACKAGE, PUBLISHER, BLOSSOM } from "./zapstore_broker.ts";
const cert="a".repeat(64);
const asset=()=>({kind:3063,pubkey:PUBLISHER,created_at:1,content:"",tags:[["i",PACKAGE],["x","b".repeat(64)],["apk_certificate_hash",cert],["version_code","12"],["url",BLOSSOM+"/"+"b".repeat(64)]]});
test("rejects stable APK, foreign publisher, certificate and host",()=>{
  for(const e of [{...asset(),pubkey:"b".repeat(64)},{...asset(),tags:asset().tags.map(t=>t[0]==="i"?["i","com.wingmanbefree.wingman_app"]:t)},{...asset(),tags:asset().tags.map(t=>t[0]==="apk_certificate_hash"?[t[0],"b".repeat(64)]:t)},{...asset(),tags:asset().tags.map(t=>t[0]==="url"?["url","https://evil.example/file"]:t)}])expect(()=>validate(e,cert)).toThrow();
});
test("broker denial propagates without retry or fallback",async()=>{
  let calls=0;await expect(signChecked(asset(),cert,async()=>{calls++;throw Error("denied");},()=>true)).rejects.toThrow("denied");expect(calls).toBe(1);
});
test("broker mutation, invalid signature and timestamp mismatch fail closed",async()=>{
  await expect(signChecked(asset(),cert,async()=>({event:{...asset(),pubkey:"x"}}),()=>true)).rejects.toThrow();
  await expect(signChecked(asset(),cert,async()=>({event:asset()}),()=>false)).rejects.toThrow();
  const proof={kind:30509,pubkey:PUBLISHER,created_at:1,content:"",tags:[["d",cert],["expiry","2"],["signature","abc"]]};
  await expect(signChecked(proof,cert,async()=>({event:{...proof,created_at:2}}),()=>true)).rejects.toThrow("timestamp changed");
});
test("valid template retains exact tags and content while asset ID changes",async()=>{
  const e=asset();const signed=await signChecked(e,cert,async()=>({event:{...e,created_at:5,id:"signed"}}),()=>true);expect(signed.id).toBe("signed");expect(signed.tags).toEqual(e.tags);
});
test("invalid certificate proof is rejected before publication",()=>expect(()=>verifyProof({kind:30509,pubkey:PUBLISHER,created_at:1,content:"",tags:[]},new Uint8Array())).toThrow());
