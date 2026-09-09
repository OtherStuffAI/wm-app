// Read-only smoke using the production pinned native socket path, no signer.
import 'dart:convert';
import '../../app/lib/src/core/tower_fips_proxy.dart';
import '../../app/lib/src/core/tower_fips_native_request.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Pass the exact approved mesh origin.');
  final proxy=await TowerFipsProxy.bind(endpoint:args.single,pageOrigin:'https://example.com');
  try {
    final request=await TowerFipsNativeRequest.open(proxy,'${args.single}/health','GET',{});
    final meta=await request.finish();
    final bytes=<int>[];
    while (true) {
      final chunk=await request.pull();
      if(chunk['done']==true) break;
      bytes.addAll(base64Decode(chunk['chunk'] as String));
      if(bytes.length>65536) throw StateError('Unexpected health body size.');
    }
    final body=jsonDecode(utf8.decode(bytes));
    if(meta['status']!=200 || body is! Map) throw StateError('Mesh health failed.');
    print('PASS production pinned FIPS socket -> live Tower health 200 JSON');
  } finally { await proxy.close(); }
}
