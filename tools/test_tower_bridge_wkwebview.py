#!/usr/bin/env python3
"""Real stock WKWebView -> production JS/Dart -> real HTTP socket integration."""
import os, pathlib, subprocess, tempfile
root=pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='wmapp-tower-wk-') as tmp:
    # Exercise the actual FD consumer together with native production JS/Dart.
    fd=pathlib.Path(os.environ.get('FLIGHT_DECK_DIR', root.parent/'flightdeck'))
    entry=pathlib.Path(tmp)/'consumer.js'
    entry.write_text("import {getSharedDb} from "+repr(str(fd/'src/db.js'))+"; import * as transport from "+repr(str(fd/'src/tower-transport.js'))+"; getSharedDb(); globalThis.fixtureTransport=transport;")
    bundle=pathlib.Path(tmp)/'consumer-bundle.js'
    subprocess.run(['bun','build',str(entry),'--target=browser','--format=iife','--define','import.meta.env={}','--define','__FLIGHT_DECK_PG_APP_NPUB__="npub1qmc3cvfz0yu2hx96nq3gp55zdan2qclealn7xshgr448d3nh6lks7zel98"','--outfile='+str(bundle)],check=True,cwd=fd)
    integration=pathlib.Path(tmp)/'integration.js'
    integration.write_text(bundle.read_text()+"\n"+(root/'tools/tower_bridge/wk_integration.js').read_text())
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
        subprocess.run([exe,port,str(integration)],check=True,timeout=55)
    finally:
        server.terminate();server.wait(timeout=5)
