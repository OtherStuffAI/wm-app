import Cocoa
import WebKit
// Separate stock WKWebView process with ephemeral storage; never touches WMapp's
// profile/keychain. The Dart harness consent callback is test-controlled.
let app = NSApplication.shared
let rpc = CommandLine.arguments[1]
let page = CommandLine.arguments[2]
let tests = try String(contentsOfFile: CommandLine.arguments[3], encoding: .utf8)
class Probe: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
  var view: WKWebView!
  var rejectedFrames = 0
  var injected = false
  func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
    if m.name == "Result" {
      let result=String(describing:m.body)
      print(result); print("Native rejected subframe messages: \(rejectedFrames)")
      fflush(stdout)
      if CommandLine.arguments.count > 4 {
        view.takeSnapshot(with:nil) { image,error in
          if let image=image, let tiff=image.tiffRepresentation, let bitmap=NSBitmapImageRep(data:tiff), let png=bitmap.representation(using:.png,properties:[:]) {
            try? png.write(to:URL(fileURLWithPath:CommandLine.arguments[4]))
          }
          exit(result.hasPrefix("PASS") && self.rejectedFrames > 0 ? 0:1)
        }
      } else { exit(result.hasPrefix("PASS") && rejectedFrames > 0 ? 0:1) }
      return
    }
    guard WingmanScriptMessagePolicy.accepts(m) else { rejectedFrames += 1; return }
    var request=URLRequest(url:URL(string:rpc+"/rpc")!)
    request.httpMethod="POST";request.httpBody=String(describing:m.body).data(using:.utf8)
    URLSession.shared.dataTask(with:request) { data,_,error in
      guard let data=data, let script=String(data:data,encoding:.utf8), error==nil else { return }
      DispatchQueue.main.async { self.view.evaluateJavaScript(script) }
    }.resume()
  }
  func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {
    if injected { return }; injected=true
    URLSession.shared.dataTask(with:URL(string:rpc+"/script")!) { data,_,_ in
      guard let data=data, let script=String(data:data,encoding:.utf8) else { return }
      DispatchQueue.main.async {
        webView.evaluateJavaScript("window.WingmanGrasp={postMessage:s=>window.webkit.messageHandlers.WingmanGrasp.postMessage(s)};"+script) { _,error in
          if let error=error { print("FAIL injection \(error)");exit(1) }
          webView.evaluateJavaScript(tests+";void 0;") { _,error in
            if let error=error {print("FAIL tests \(error)");exit(1)}
          }
        }
      }
    }.resume()
  }
  func start() {
    let c=WKWebViewConfiguration();c.websiteDataStore = .nonPersistent()
    c.userContentController.add(self,name:"WingmanGrasp");c.userContentController.add(self,name:"Result")
    view=WKWebView(frame:NSRect(x:0,y:0,width:1300,height:900),configuration:c);view.navigationDelegate=self
    view.load(URLRequest(url:URL(string:page)!))
  }
}
let p=Probe();p.start()
DispatchQueue.main.asyncAfter(deadline:.now()+55){print("FAIL TIMEOUT");exit(2)}
app.run()
