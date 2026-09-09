import 'dart:io';
import '../app/lib/src/features/browser/tower_fips_bridge_script.dart';
void main(List<String> args) {
 stdout.write(towerFipsBridgeScript(args.isEmpty ? 'test-document' : args[0],
  args.length < 2 ? 'https://example.com' : args[1]));
}
