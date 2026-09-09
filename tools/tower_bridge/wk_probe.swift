import Cocoa
import WebKit
// Uses stock WKWebView. No private settings, TLS bypass, or mixed-content flags.
let app = NSApplication.shared
let rpcPort = CommandLine.arguments[1]
let tests = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
class Probe: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
 var view: WKWebView!
 var iframeRejected = false
 func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
  if m.name == "Result" { if !iframeRejected { print("FAIL iframe gate was not exercised"); exit(1) }; print(m.body); fflush(stdout); exit(String(describing:m.body).hasPrefix("PASS") ? 0 : 1) }
  guard WingmanScriptMessagePolicy.accepts(m) else { iframeRejected=true; return }
  var request=URLRequest(url:URL(string:"http://127.0.0.1:\(rpcPort)/rpc")!)
  request.httpMethod="POST";request.httpBody=String(describing:m.body).data(using:.utf8)
  URLSession.shared.dataTask(with:request) { data,_,error in
    guard let data=data, let script=String(data:data,encoding:.utf8), error==nil else { return }
    DispatchQueue.main.async { self.view.evaluateJavaScript(script) }
  }.resume()
 }
 func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {
  URLSession.shared.dataTask(with:URL(string:"http://127.0.0.1:\(rpcPort)/script")!) { data,_,_ in
    guard let data=data, let script=String(data:data,encoding:.utf8) else { return }
    DispatchQueue.main.async {
      webView.evaluateJavaScript("window.WingmanTower={postMessage:s=>window.webkit.messageHandlers.WingmanTower.postMessage(s)};"+script) { _,error in
        if let error=error { print("FAIL injection \(error)");exit(1) }
        webView.evaluateJavaScript(tests+";void 0;") { _,error in
          if let error=error { print("FAIL test script \(error)");exit(1) }
        }
      }
    }
  }.resume()
 }
 func start() {
  let c=WKWebViewConfiguration();c.userContentController.add(self,name:"WingmanTower");c.userContentController.add(self,name:"Result")
  view=WKWebView(frame:NSRect(x:0,y:0,width:500,height:400),configuration:c);view.navigationDelegate=self
  view.load(URLRequest(url:URL(string:"https://example.com")!))
 }
}
let p=Probe();p.start()
DispatchQueue.main.asyncAfter(deadline:.now()+45){print("FAIL TIMEOUT");exit(2)}
app.run()
