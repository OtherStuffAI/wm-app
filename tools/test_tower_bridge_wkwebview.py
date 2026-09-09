#!/usr/bin/env python3
"""Real stock WKWebView -> production JS/Dart -> real HTTP socket integration."""
import pathlib, subprocess, tempfile
root=pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='wmapp-tower-wk-') as tmp:
    exe=str(pathlib.Path(tmp)/'probe')
    main=pathlib.Path(tmp)/'main.swift'
    main.write_text((root/'tools/tower_bridge/wk_probe.swift').read_text())
    policy=root/'packages/webview_flutter_wkwebview/darwin/webview_flutter_wkwebview/Sources/webview_flutter_wkwebview/WingmanScriptMessagePolicy.swift'
    subprocess.run(['swiftc',str(main),str(policy),'-o',exe],check=True)
    server=subprocess.Popen(['dart','--packages='+str(root/'app/.dart_tool/package_config.json'),
        str(root/'tools/tower_bridge/fixture_server.dart')],stdout=subprocess.PIPE,text=True,cwd=root)
    try:
        port=server.stdout.readline().strip()
        if not port.isdigit(): raise RuntimeError('Fixture failed to start')
        subprocess.run([exe,port,str(root/'tools/tower_bridge/wk_integration.js')],check=True,timeout=55)
    finally:
        server.terminate();server.wait(timeout=5)
