import Foundation
import UIKit
import WebKit

private final class BrowserLog {
    private let file: URL?
    init(directory: String) {
        file = directory.isEmpty ? nil : URL(fileURLWithPath: directory).appendingPathComponent("browser.log")
    }
    func write(_ event: String, handle: Int64, url: String? = nil, detail: String = "") {
        guard let file else { return }
        let line = "time=\(Date().timeIntervalSince1970) view=\(handle) event=\(event) url=\(browserLocation(url)) \(detail)\n"
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
            let output = try FileHandle(forWritingTo: file)
            defer { try? output.close() }
            try output.seekToEnd(); try output.write(contentsOf: Data(line.utf8))
        } catch { NSLog("[WebView] log write failed") }
    }
}

private final class BrowserCookies: NSObject, WKHTTPCookieStoreObserver {
    let package: String
    let dataStore = WKWebsiteDataStore.nonPersistent()
    private let file: BrowserCookieFile
    private let log: BrowserLog
    private var queue: [(@escaping () -> Void) -> Void] = []
    private var busy = false
    var live = true
    var accepts = true
    var cached: [HTTPCookie] = []

    init(package: String, dataDirectory: String, log: BrowserLog) {
        self.package = package; self.log = log
        file = BrowserCookieFile(dataDirectory: dataDirectory)
        super.init()
        dataStore.httpCookieStore.add(self)
        if let values = try? file.load() {
            cached = values
            for cookie in cached {
                perform { done in self.dataStore.httpCookieStore.setCookie(cookie, completionHandler: done) }
            }
            KuDroidWebViewBridge.shared.updateCookies(package, cached)
        }
    }
    func perform(_ action: @escaping (@escaping () -> Void) -> Void) {
        guard live else { return }
        queue.append(action); drain()
    }
    private func drain() {
        guard live, !busy, !queue.isEmpty else { return }
        busy = true
        let action = queue.removeFirst()
        action { [weak self] in
            guard let self else { return }
            self.busy = false; self.drain()
        }
    }
    func refresh(_ completion: @escaping () -> Void = {}) {
        dataStore.httpCookieStore.getAllCookies { [weak self] values in
            guard let self, self.live else { completion(); return }
            self.cached = self.accepts ? values : []
            KuDroidWebViewBridge.shared.updateCookies(self.package, self.cached)
            self.save(); completion()
        }
    }
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        guard live else { return }
        if accepts { refresh() }
        else { clear(sessionOnly: false) {} }
    }
    func clear(sessionOnly: Bool, completion: @escaping () -> Void) {
        perform { done in
            self.dataStore.httpCookieStore.getAllCookies { values in
                let group = DispatchGroup()
                for cookie in values where !sessionOnly || cookie.expiresDate == nil {
                    group.enter(); self.dataStore.httpCookieStore.delete(cookie) { group.leave() }
                }
                group.notify(queue: .main) { self.refresh { completion(); done() } }
            }
        }
    }
    func set(url: String, value: String, completion: @escaping (Bool) -> Void) {
        guard accepts, let url = URL(string: url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { completion(false); return }
        let values = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": value], for: url)
        guard !values.isEmpty else { completion(false); return }
        perform { done in
            let group = DispatchGroup()
            for cookie in values { group.enter(); self.dataStore.httpCookieStore.setCookie(cookie) { group.leave() } }
            group.notify(queue: .main) { self.refresh { completion(true); done() } }
        }
    }
    func save() {
        guard live else { return }
        do { try file.save(cached) } catch { log.write("cookie-save-failed", handle: 0) }
    }
    func dispose() { save(); live = false; queue.removeAll(); dataStore.httpCookieStore.remove(self) }
}

private final class BrowserEntry: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let handle: Int64
    let cookies: BrowserCookies
    let log: BrowserLog
    weak var controller: UIViewController?
    var web: WKWebView?
    let pane = UIView()
    let errorLabel = UILabel()
    let locationLabel = UILabel()
    private let back = UIButton(type: .system)
    private let forward = UIButton(type: .system)
    private var observations: [NSKeyValueObservation] = []
    private var pending: [Int64: (Bool) -> Void] = [:]
    private var nextRequest: Int64 = 1
    private var pendingRedirects = Set<Int64>()
    private var deferredEvents: [(Int32, Int64, String, String, Int32)] = []
    private var initialURL: String?
    private var initialHTML = false
    private var lastPolicyURL: String?
    var visible = false
    var javaScript = false
    var domStorage = false
    var mediaGesture = true
    var allowFiles = false
    var userAgent: String?
    var rectangle = CGRect.zero
    var viewport = CGSize.zero
    private var disposed = false
    private var dialogs: [UUID: () -> Void] = [:]
    private weak var alert: UIAlertController?

    init(handle: Int64, cookies: BrowserCookies, log: BrowserLog, controller: UIViewController?) {
        self.handle = handle; self.cookies = cookies; self.log = log; self.controller = controller
        super.init()
    }
    var active: Bool { !disposed && (handle < 0 || kudroid_webview_active(handle) != 0) }
    func build() {
        guard web == nil, active else { return }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = cookies.dataStore
        configuration.mediaTypesRequiringUserActionForPlayback = mediaGesture ? .all : []
        configuration.preferences.javaScriptEnabled = javaScript
        configuration.defaultWebpagePreferences.allowsContentJavaScript = javaScript
        let content = WKUserContentController()
        content.add(self, name: "browserConsole")
        content.addUserScript(WKUserScript(source: "window.addEventListener('error',function(e){window.webkit.messageHandlers.browserConsole.postMessage({source:e.filename||'',line:e.lineno||0,kind:'error'});});window.addEventListener('unhandledrejection',function(){window.webkit.messageHandlers.browserConsole.postMessage({source:location.href,line:0,kind:'rejection'});});", injectionTime: .atDocumentStart, forMainFrameOnly: false))
        configuration.userContentController = content
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self; view.uiDelegate = self; view.customUserAgent = userAgent
        view.allowsBackForwardNavigationGestures = true
        web = view
        pane.backgroundColor = .systemBackground; pane.clipsToBounds = true
        let close = button("xmark", label: "Close browser") { [weak self] in self?.close() }
        configure(back, "chevron.left", "Back") { [weak self] in self?.go(-1) }
        configure(forward, "chevron.right", "Forward") { [weak self] in self?.go(1) }
        let reload = button("arrow.clockwise", label: "Reload") { [weak self] in self?.reload() }
        locationLabel.font = .preferredFont(forTextStyle: .caption1); locationLabel.lineBreakMode = .byTruncatingMiddle
        let toolbar = UIStackView(arrangedSubviews: [close, back, forward, reload, locationLabel])
        toolbar.alignment = .center; toolbar.spacing = 4
        [toolbar, view, errorLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; pane.addSubview($0) }
        errorLabel.textAlignment = .center; errorLabel.numberOfLines = 0; errorLabel.backgroundColor = .systemBackground; errorLabel.isHidden = true
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: pane.safeAreaLayoutGuide.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: pane.safeAreaLayoutGuide.leadingAnchor, constant: 4),
            toolbar.trailingAnchor.constraint(equalTo: pane.safeAreaLayoutGuide.trailingAnchor, constant: -4),
            toolbar.heightAnchor.constraint(equalToConstant: 44),
            view.topAnchor.constraint(equalTo: toolbar.bottomAnchor), view.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: pane.trailingAnchor), view.bottomAnchor.constraint(equalTo: pane.keyboardLayoutGuide.topAnchor),
            errorLabel.topAnchor.constraint(equalTo: view.topAnchor), errorLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
        ])
        observations = [view.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
            self?.post(8, flags: Int32(view.estimatedProgress * 100))
        }, view.observe(\.title, options: [.new]) { [weak self] view, _ in self?.post(6, text: view.title ?? "") },
        view.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in self?.history() },
        view.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in self?.history() }]
        history(); layout()
    }
    private func configure(_ button: UIButton, _ image: String, _ label: String, action: @escaping () -> Void) {
        button.setImage(UIImage(systemName: image), for: .normal); button.accessibilityLabel = label
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }
    private func button(_ image: String, label: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system); configure(button, image, label, action: action); return button
    }
    func layout() {
        guard active, let root = controller?.view else { pane.removeFromSuperview(); return }
        if handle < 0 { pane.frame = root.bounds }
        else if viewport.width > 0 && viewport.height > 0 {
            let scaled = CGRect(x: rectangle.minX * root.bounds.width / viewport.width,
                y: rectangle.minY * root.bounds.height / viewport.height,
                width: rectangle.width * root.bounds.width / viewport.width,
                height: rectangle.height * root.bounds.height / viewport.height)
            guard [scaled.minX, scaled.minY, scaled.width, scaled.height].allSatisfy({ $0.isFinite }) else { return }
            pane.frame = scaled
        }
        if visible, web != nil, !pane.frame.isEmpty {
            if pane.superview !== root { root.addSubview(pane) }
            root.bringSubviewToFront(pane)
        } else { pane.removeFromSuperview() }
    }
    func settings() {
        web?.customUserAgent = userAgent
        web?.configuration.preferences.javaScriptEnabled = javaScript
    }
    func load(_ text: String, headers: [String: String]) {
        guard active, let target = URL(string: text), let scheme = target.scheme?.lowercased() else {
            failed(NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL)); return
        }
        guard ["http", "https", "about", "data"].contains(scheme) else {
            failed(NSError(domain: NSURLErrorDomain, code: NSURLErrorUnsupportedURL)); return
        }
        build(); initialURL = target.absoluteString; initialHTML = false; lastPolicyURL = nil
        errorLabel.isHidden = true
        log.write("load", handle: handle, url: text)
        var request = URLRequest(url: target); request.allHTTPHeaderFields = headers
        cookies.perform { done in if self.active { self.web?.load(request) }; done() }
        layout()
    }
    func html(_ text: String, base: String?) {
        build(); initialHTML = true; initialURL = nil; lastPolicyURL = nil; errorLabel.isHidden = true
        log.write("html", handle: handle, url: base)
        cookies.perform { done in if self.active { self.web?.loadHTMLString(text, baseURL: base.flatMap(URL.init(string:))) }; done() }
        layout()
    }
    func post(_ event: Int32, request: Int64 = 0, text: String = "", detail: String = "", flags: Int32 = 0) {
        guard active, handle > 0 else { return }
        if !pendingRedirects.isEmpty && event != 1 { deferredEvents.append((event, request, text, detail, flags)); return }
        text.withCString { text in detail.withCString { detail in _ = kudroid_webview_post(handle, event, request, text, detail, flags) } }
    }
    private func history() {
        guard let web else { return }
        back.isEnabled = web.canGoBack; forward.isEnabled = web.canGoForward
        locationLabel.text = web.url?.host ?? web.title ?? "Browser"
        let detail = "{\"back\":\(web.backForwardList.backList.count),\"forward\":\(web.backForwardList.forwardList.count)}"
        post(5, text: web.url?.absoluteString ?? "", detail: detail)
    }
    func go(_ offset: Int) {
        guard let web, let item = web.backForwardList.item(at: offset) else { return }
        log.write(offset < 0 ? "back" : "forward", handle: handle, url: item.url.absoluteString)
        errorLabel.isHidden = true; initialURL = nil; initialHTML = false; web.go(to: item)
    }
    func reload() { log.write("reload", handle: handle, url: web?.url?.absoluteString); errorLabel.isHidden = true; web?.reload() }
    func close() {
        log.write("close", handle: handle, url: web?.url?.absoluteString)
        visible = false; web?.stopLoading(); cancelDecisions(); pane.removeFromSuperview()
        if handle < 0 { KuDroidWebViewBridge.shared.remove(handle) } else { post(9) }
    }
    func evaluate(_ script: String, request: Int64) {
        build()
        web?.evaluateJavaScript(script) { [weak self] value, error in
            guard let self, self.active else { return }
            var text = "null"
            if error == nil, let value, let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
               let json = String(data: data, encoding: .utf8) { text = json }
            if error != nil { self.log.write("script-error", handle: self.handle, url: self.web?.url?.absoluteString) }
            self.post(10, request: request, text: text)
        }
    }
    private func requestDecision(_ url: String, method: String, headers: [String: String], flags: Int32,
                                 redirect: Bool = false, completion: @escaping (Bool) -> Void) {
        guard active else { completion(false); return }
        if handle < 0 { completion(true); return }
        let request = nextRequest; nextRequest += 1
        pending[request] = completion
        if redirect { pendingRedirects.insert(request) }
        let metadata = (try? JSONSerialization.data(withJSONObject: ["method": method, "headers": headers])) ?? Data()
        let detail = String(data: metadata, encoding: .utf8) ?? "{}"
        log.write("navigation-request", handle: handle, url: url, detail: "request=\(request) redirect=\(redirect)")
        url.withCString { url in detail.withCString { detail in
            if kudroid_webview_post(handle, 1, request, url, detail, flags) == 0 { resolve(request, allow: false) }
        } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.pending[request] != nil else { return }
            self.log.write("navigation-timeout", handle: self.handle, detail: "request=\(request)")
            self.resolve(request, allow: false)
        }
    }
    func resolve(_ request: Int64, allow: Bool) {
        guard let completion = pending.removeValue(forKey: request) else { return }
        let redirect = pendingRedirects.remove(request) != nil
        log.write("navigation-decision", handle: handle, detail: "request=\(request) allow=\(allow)")
        completion(allow)
        if redirect && pendingRedirects.isEmpty {
            let queued = deferredEvents; deferredEvents.removeAll()
            if allow { for event in queued { post(event.0, request: event.1, text: event.2, detail: event.3, flags: event.4) } }
        }
    }
    private func cancelDecisions() {
        let completions = Array(pending.values); pending.removeAll(); pendingRedirects.removeAll(); deferredEvents.removeAll()
        for completion in completions { completion(false) }
    }
    func dispose() {
        guard !disposed else { return }
        disposed = true; cancelDecisions(); pane.removeFromSuperview()
        let cancellations = Array(dialogs.values); dialogs.removeAll()
        for cancel in cancellations { cancel() }
        alert?.dismiss(animated: false); alert = nil
        observations.forEach { $0.invalidate() }; observations.removeAll()
        web?.stopLoading(); web?.configuration.userContentController.removeScriptMessageHandler(forName: "browserConsole")
        web?.navigationDelegate = nil; web?.uiDelegate = nil; web = nil
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        guard active, let target = navigationAction.request.url else { decisionHandler(.cancel, preferences); return }
        preferences.allowsContentJavaScript = javaScript
        let main = navigationAction.targetFrame?.isMainFrame ?? true
        let text = target.absoluteString
        if main && (initialURL == text || initialHTML) {
            initialURL = nil; initialHTML = false; lastPolicyURL = text; decisionHandler(.allow, preferences); return
        }
        lastPolicyURL = text
        if navigationAction.request.httpMethod?.uppercased() == "POST" { decisionHandler(.allow, preferences); return }
        let flags: Int32 = (main ? 1 : 0) | (navigationAction.navigationType == .linkActivated ? 2 : 0)
        requestDecision(text, method: navigationAction.request.httpMethod ?? "GET", headers: navigationAction.request.allHTTPHeaderFields ?? [:], flags: flags) { [weak self] allow in
            guard let self, self.active, allow else { decisionHandler(.cancel, preferences); return }
            let scheme = target.scheme?.lowercased() ?? ""
            if ["http", "https", "about", "data"].contains(scheme) { decisionHandler(.allow, preferences) }
            else {
                decisionHandler(.cancel, preferences)
                if !["file", "content", "javascript", "android.resource"].contains(scheme) {
                    self.log.write("external-scheme", handle: self.handle, url: text)
                    UIApplication.shared.open(target, options: [:])
                }
            }
        }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard active else { return }
        errorLabel.isHidden = true; history()
        let url = webView.url?.absoluteString ?? lastPolicyURL ?? ""
        log.write("started", handle: handle, url: url); post(2, text: url)
    }
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        guard active else { return }
        guard let url = webView.url?.absoluteString, url != lastPolicyURL else { return }
        lastPolicyURL = url
        requestDecision(url, method: "", headers: [:], flags: 5, redirect: true) { [weak webView] allow in
            if !allow { webView?.stopLoading() }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard active else { decisionHandler(.cancel); return }
        if let response = navigationResponse.response as? HTTPURLResponse {
            log.write("response", handle: handle, url: response.url?.absoluteString, detail: "status=\(response.statusCode)")
            if response.statusCode >= 400 {
                var headers: [String: String] = [:]
                for (key, value) in response.allHeaderFields { headers[String(describing: key)] = String(describing: value) }
                let metadata: [String: Any] = ["mime": response.mimeType ?? "", "encoding": response.textEncodingName ?? "", "headers": headers]
                let bytes = (try? JSONSerialization.data(withJSONObject: metadata)) ?? Data()
                let flags = Int32(response.statusCode) | (navigationResponse.isForMainFrame ? 65536 : 0)
                post(7, text: response.url?.absoluteString ?? "", detail: String(data: bytes, encoding: .utf8) ?? "{}", flags: flags)
            }
        }
        decisionHandler(active ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard active else { return }
        history(); cookies.refresh()
        let url = webView.url?.absoluteString ?? ""
        log.write("finished", handle: handle, url: url); post(3, text: url)
    }
    private func failed(_ error: Error) {
        guard active else { return }
        let value = error as NSError
        if value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled { return }
        log.write("load-error", handle: handle, url: web?.url?.absoluteString, detail: "domain=\(value.domain) code=\(value.code)")
        errorLabel.text = "Page couldn’t load. Tap Reload to try again."; errorLabel.isHidden = false
        var code: Int32 = -1
        if value.domain == NSURLErrorDomain {
            if value.code == NSURLErrorTimedOut { code = -8 }
            else if value.code == NSURLErrorCannotFindHost || value.code == NSURLErrorDNSLookupFailed { code = -2 }
            else if value.code == NSURLErrorCannotConnectToHost || value.code == NSURLErrorNotConnectedToInternet { code = -6 }
            else if value.code == NSURLErrorUnsupportedURL || value.code == NSURLErrorBadURL { code = -10 }
            else if value.code <= NSURLErrorSecureConnectionFailed && value.code >= NSURLErrorClientCertificateRequired { code = -11 }
        }
        post(4, text: web?.url?.absoluteString ?? lastPolicyURL ?? "", detail: value.localizedDescription, flags: code)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard active else { return }
        log.write("content-process-terminated", handle: handle, url: webView.url?.absoluteString)
        cancelDecisions(); failed(NSError(domain: "WebContent", code: -1))
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { initialURL = nil; initialHTML = false; webView.load(navigationAction.request) }
        return nil
    }
    func webViewDidClose(_ webView: WKWebView) { close() }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard active, let data = message.body as? [String: Any] else { return }
        let source = browserLocation(data["source"] as? String)
        let line = data["line"] as? Int32 ?? 0
        let requestedKind = data["kind"] as? String ?? ""
        let kind = ["error", "rejection"].contains(requestedKind) ? requestedKind : "message"
        log.write("console", handle: handle, url: source, detail: "kind=\(kind) line=\(line)")
        post(13, text: "JavaScript \(kind)", detail: source, flags: line)
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard let controller, active, controller.presentedViewController == nil else { completionHandler(); return }
        let alert = UIAlertController(title: webView.url?.host, message: message, preferredStyle: .alert)
        let token = UUID(); dialogs[token] = completionHandler; self.alert = alert
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.dialogs.removeValue(forKey: token)?() }); controller.present(alert, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard let controller, active, controller.presentedViewController == nil else { completionHandler(false); return }
        let alert = UIAlertController(title: webView.url?.host, message: message, preferredStyle: .alert)
        let token = UUID(); dialogs[token] = { completionHandler(false) }; self.alert = alert
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.dialogs.removeValue(forKey: token)?() })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            if self?.dialogs.removeValue(forKey: token) != nil { completionHandler(true) }
        }); controller.present(alert, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard let controller, active, controller.presentedViewController == nil else { completionHandler(nil); return }
        let alert = UIAlertController(title: webView.url?.host, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        let token = UUID(); dialogs[token] = { completionHandler(nil) }; self.alert = alert
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.dialogs.removeValue(forKey: token)?() })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self, weak alert] _ in
            if self?.dialogs.removeValue(forKey: token) != nil { completionHandler(alert?.textFields?.first?.text) }
        })
        controller.present(alert, animated: true)
    }
}

final class KuDroidWebViewBridge {
    static let shared = KuDroidWebViewBridge()
    private weak var controller: UIViewController?
    private var entries: [Int64: BrowserEntry] = [:]
    private var stores: [String: BrowserCookies] = [:]
    private let lock = NSLock()
    private var packages: [Int64: String] = [:]
    private var cookieMirror: [String: [HTTPCookie]] = [:]
    private var defaultAgent: String?
    private var warming: WKWebView?
    private var nextExternal: Int64 = -1

    func register(_ controller: UIViewController) {
        self.controller = controller
        var host = KuDroidWebViewHost(create: browserCreate, command: browserCommand, cookies: browserCookies, user_agent: browserUserAgent, reset: browserReset)
        kudroid_set_webview_host(&host)
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        warming = WKWebView(frame: .zero, configuration: configuration)
        warming?.evaluateJavaScript("navigator.userAgent") { [weak self] value, _ in
            guard let self else { return }
            self.lock.lock(); self.defaultAgent = value as? String; self.lock.unlock(); self.warming = nil
        }
    }
    func bind(_ handle: Int64, package: String) { lock.lock(); packages[handle] = package; lock.unlock() }
    fileprivate func updateCookies(_ package: String, _ cookies: [HTTPCookie]) { lock.lock(); cookieMirror[package] = cookies; lock.unlock() }
    fileprivate func cookieHeader(_ handle: Int64, _ text: String?) -> String? {
        lock.lock(); let values = packages[handle].flatMap { cookieMirror[$0] } ?? []; lock.unlock()
        return browserCookieHeader(values, url: text)
    }
    fileprivate func agent() -> String? { lock.lock(); defer { lock.unlock() }; return defaultAgent }
    fileprivate func create(_ handle: Int64, package: String, dataDirectory: String, logDirectory: String) {
        guard kudroid_webview_active(handle) != 0 else { return }
        let log = BrowserLog(directory: logDirectory)
        let store = stores[package] ?? BrowserCookies(package: package, dataDirectory: dataDirectory, log: log)
        stores[package] = store
        entries[handle] = BrowserEntry(handle: handle, cookies: store, log: log, controller: controller)
        log.write("created", handle: handle)
    }
    fileprivate func command(_ handle: Int64, _ command: Int32, _ request: Int64,
        _ text: String?, _ detail: String?, _ a: Double, _ b: Double, _ c: Double, _ d: Double) {
        if command == 10 { remove(handle); return }
        guard let entry = entries[handle], entry.active else { return }
        switch command {
        case 1:
            let headers = detail.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } ?? [:]
            entry.load(text ?? "", headers: headers)
        case 2: entry.html(text ?? "", base: detail)
        case 3:
            entry.userAgent = text; entry.javaScript = a != 0; entry.domStorage = b != 0
            entry.mediaGesture = c != 0; entry.allowFiles = d != 0; entry.settings()
        case 4:
            let dimensions = (text ?? "").split(separator: ",").compactMap { Double($0) }
            if dimensions.count == 2, dimensions[0] > 0, dimensions[1] > 0, [a,b,c,d].allSatisfy({ $0.isFinite }) {
                entry.viewport = CGSize(width: dimensions[0], height: dimensions[1]); entry.rectangle = CGRect(x: a, y: b, width: c, height: d); entry.layout()
            }
        case 5: entry.visible = a != 0; entry.layout()
        case 6, 7:
            if a.isFinite && a >= Double(Int32.min) && a <= Double(Int32.max) { entry.go(Int(a)) }
        case 8: entry.reload()
        case 9: entry.web?.stopLoading()
        case 11: entry.evaluate(text ?? "", request: request)
        case 12: entry.resolve(request, allow: a != 0)
        case 13: entry.cookies.set(url: text ?? "", value: detail ?? "") { [weak entry] success in entry?.post(11, request: request, flags: success ? 1 : 0) }
        case 14: entry.cookies.clear(sessionOnly: a != 0) { [weak entry] in entry?.post(11, request: request, flags: 1) }
        case 15: entry.cookies.perform { done in entry.cookies.refresh { done() } }
        case 16:
            entry.cookies.accepts = a != 0
            if a == 0 { entry.cookies.clear(sessionOnly: false) {} }
        default: break
        }
    }
    fileprivate func remove(_ handle: Int64) {
        entries.removeValue(forKey: handle)?.dispose(); lock.lock(); packages.removeValue(forKey: handle); lock.unlock()
    }
    fileprivate func reset() {
        for handle in Array(entries.keys) where handle < 0 || kudroid_webview_active(handle) == 0 { remove(handle) }
        for package in Array(stores.keys) where !entries.values.contains(where: { $0.cookies.package == package }) {
            stores.removeValue(forKey: package)?.dispose(); lock.lock(); cookieMirror.removeValue(forKey: package); lock.unlock()
        }
    }
    func detach() { kudroid_set_webview_host(nil); for handle in Array(entries.keys) { remove(handle) }; reset(); controller = nil; warming = nil }
    func layout() { for entry in entries.values { entry.layout() } }
    func open(_ url: URL) {
        guard let controller else { return }
        let package = String(cString: kudroid_current_log_dir()).components(separatedBy: "/").last ?? ""
        let log = BrowserLog(directory: String(cString: kudroid_current_log_dir()))
        let root = String(cString: kudroid_android_root_path())
        let store = stores[package] ?? BrowserCookies(package: package, dataDirectory: root + "/data/data/" + package, log: log)
        stores[package] = store
        let handle = nextExternal; nextExternal -= 1
        let entry = BrowserEntry(handle: handle, cookies: store, log: log, controller: controller)
        entry.javaScript = true; entry.domStorage = true; entry.visible = true
        entries[handle] = entry; entry.load(url.absoluteString, headers: [:]); entry.layout()
    }
}

private func browserCreate(_ handle: Int64, _ package: UnsafePointer<CChar>?, _ data: UnsafePointer<CChar>?, _ logs: UnsafePointer<CChar>?) {
    let package = package.map { String(cString: $0) } ?? ""
    let data = data.map { String(cString: $0) } ?? ""
    let logs = logs.map { String(cString: $0) } ?? ""
    KuDroidWebViewBridge.shared.bind(handle, package: package)
    DispatchQueue.main.async { KuDroidWebViewBridge.shared.create(handle, package: package, dataDirectory: data, logDirectory: logs) }
}
private func browserCommand(_ handle: Int64, _ command: Int32, _ request: Int64, _ text: UnsafePointer<CChar>?,
                            _ detail: UnsafePointer<CChar>?, _ a: Double, _ b: Double, _ c: Double, _ d: Double) {
    let text = text.map { String(cString: $0) }; let detail = detail.map { String(cString: $0) }
    DispatchQueue.main.async { KuDroidWebViewBridge.shared.command(handle, command, request, text, detail, a, b, c, d) }
}
private func browserCookies(_ handle: Int64, _ url: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let value = KuDroidWebViewBridge.shared.cookieHeader(handle, url.map { String(cString: $0) }) else { return nil }
    return strdup(value)
}
private func browserUserAgent() -> UnsafeMutablePointer<CChar>? {
    guard let value = KuDroidWebViewBridge.shared.agent() else { return nil }; return strdup(value)
}
private func browserReset() { DispatchQueue.main.async { KuDroidWebViewBridge.shared.reset() } }
