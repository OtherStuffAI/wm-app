// Test-only real socket backend and native RPC relay. Never used by WMapp.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../app/lib/src/core/tower_fips_proxy.dart';
import '../../app/lib/src/features/browser/tower_fips_browser_bridge.dart';

Future<void> main(List<String> args) async {
  var cancellationMessages = 0;
  final tower = await HttpServer.bind(InternetAddress.loopbackIPv4,0);
  tower.listen((r) async {
    if (r.headers.value('host') != 'npub1qmc3cvfz0yu2hx96nq3gp55zdan2qclealn7xshgr448d3nh6lks7zel98.fips:8787' ||
        r.headers.value('origin') != null || r.headers.value('cookie') != null) {
      r.response.statusCode=400; await r.response.close(); return;
    }
    if (r.uri.path == '/health') {
      r.response.headers.contentType=ContentType.json;
      r.response.write(jsonEncode({'service_npub':'npub1qmc3cvfz0yu2hx96nq3gp55zdan2qclealn7xshgr448d3nh6lks7zel98'}));
      await r.response.close();
    } else if (r.uri.path == '/cancel-count') {
      r.response.headers.contentType=ContentType.json;
      r.response.write(jsonEncode(cancellationMessages)); await r.response.close();
    } else if (r.uri.path == '/events') {
      r.response.headers.contentType=ContentType('text','event-stream');
      r.response.bufferOutput=false;
      for (final byte in utf8.encode('id: 1\ndata: café\n\n')) {
        r.response.add([byte]); await r.response.flush();
        await Future<void>.delayed(const Duration(milliseconds:2));
      }
      // Deliberately never finish SSE: a whole-body-buffering adapter times out.
    } else if (r.uri.path == '/redirect') {
      r.response.statusCode=302; r.response.headers.set('location','https://public.example');
      await r.response.close();
    } else if (r.uri.path == '/hang') {
      // Deliberately never send headers; AbortSignal must tear down this request.
    } else {
      if (r.headers.value('authorization') != 'Nostr signed-mesh-target') {
        r.response.statusCode=401; await r.response.close(); return;
      }
      final body=await r.fold<List<int>>([], (a,b)=>a..addAll(b));
      r.response.statusCode=201;
      r.response.headers.contentType=ContentType.binary;
      r.response.headers.set('content-disposition','attachment; filename=bytes.bin');
      r.response.add(body); await r.response.close();
    }
  });
  final rpc=await HttpServer.bind(InternetAddress.loopbackIPv4,0);
  final replies=<String,Completer<String>>{};
  final bridge=TowerFipsBrowserBridge(pageOrigin:'https://example.com',
    approve:(_,__)async=>true,prepare:(_)async=>null,
    bindProxy:(endpoint,origin)=>TowerFipsProxy.bind(endpoint:endpoint,pageOrigin:origin,
      clientFactory:()=>HttpClient()..connectionFactory=(url,host,port)=>
        Socket.startConnect(InternetAddress.loopbackIPv4,tower.port)),
    reply:(script)async {
      final arguments=jsonDecode('[${script.substring(script.indexOf('(')+1,script.length-1)}]') as List;
      replies.remove(arguments[1])?.complete(script);
    });
  rpc.listen((r) async {
    if(r.uri.path=='/script') { r.response.write(bridge.script); await r.response.close(); return; }
    final message=await utf8.decoder.bind(r).join();
    final decoded = jsonDecode(message) as Map;
    final id=decoded['id'] as String;
    if (decoded['method'] == 'cancel') cancellationMessages++;
    if (decoded['method'] == 'open' && decoded['params']['url'].endsWith('/slow-open')) {
      await Future<void>.delayed(const Duration(milliseconds:500));
    }
    final completer=Completer<String>(); replies[id]=completer;
    unawaited(bridge.receive(message));
    try { r.response.write(await completer.future.timeout(const Duration(seconds:20))); }
    catch (_) { r.response.statusCode=500; }
    await r.response.close();
  });
  stdout.writeln(rpc.port);
}
