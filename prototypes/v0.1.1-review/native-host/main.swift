import AppKit
import CoreGraphics
import WebKit

// Standalone effect reviewer. Never imports the production app or its bridge.
struct Wing: Codable {
    let x: Double
    let width: Double
}

struct NotchGeometry: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let hardwareLeft: Double
    let hardwareRight: Double
    let exclusionLeft: Double
    let exclusionRight: Double
    let exclusionWidth: Double
    let leftWing: Wing
    let rightWing: Wing
    let hasHardwareNotch: Bool
}

struct ScreenGeometry: Codable {
    let width: Double
    let height: Double
    let displayID: UInt32
    let builtIn: Bool
}

struct ReviewGeometry: Encodable {
    let native = true
    let notch: NotchGeometry
    let screen: ScreenGeometry

    static func selectedScreen() -> NSScreen? {
        NSScreen.screens.first { CGDisplayIsBuiltin(displayID($0)) != 0 }
            ?? NSScreen.main ?? NSScreen.screens.first
    }

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func read(_ screen: NSScreen) -> ReviewGeometry {
        let frame = screen.frame
        let safeTop = screen.safeAreaInsets.top
        let leftArea = screen.auxiliaryTopLeftArea
        let rightArea = screen.auxiliaryTopRightArea
        let hasNotch = safeTop > 0 && leftArea != nil && rightArea != nil
        let hardwareLeft = hasNotch ? leftArea!.maxX - frame.minX : frame.width / 2
        let hardwareRight = hasNotch ? rightArea!.minX - frame.minX : frame.width / 2
        let exclusionWidth = hasNotch ? hardwareRight - hardwareLeft + 4 : 0
        let exclusionLeft = hasNotch ? hardwareLeft - 2 : hardwareLeft
        let exclusionRight = hasNotch ? hardwareRight + 2 : hardwareRight
        let width = hasNotch ? exclusionWidth + 88 : 277
        let x = (hardwareLeft + hardwareRight) / 2 - width / 2
        let wingWidth = hasNotch ? 44.0 : width / 2
        return ReviewGeometry(
            notch: NotchGeometry(
                x: x, y: 0, width: width, height: max(32, safeTop),
                hardwareLeft: hardwareLeft, hardwareRight: hardwareRight,
                exclusionLeft: exclusionLeft, exclusionRight: exclusionRight,
                exclusionWidth: exclusionWidth,
                leftWing: Wing(x: x, width: wingWidth),
                rightWing: Wing(x: hasNotch ? exclusionRight : x + width / 2, width: wingWidth),
                hasHardwareNotch: hasNotch
            ),
            screen: ScreenGeometry(width: frame.width, height: frame.height,
                                   displayID: displayID(screen), builtIn: CGDisplayIsBuiltin(displayID(screen)) != 0)
        )
    }

    func json(pretty: Bool = false) throws -> String {
        let encoder = JSONEncoder()
        if pretty { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

final class ReviewWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { NSApp.terminate(nil) }
        else { super.keyDown(with: event) }
    }
}

final class ReviewDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private var window: ReviewWindow?
    private var webView: WKWebView?
    private var prototypeRoot: URL?
    private var originalPresentation: NSApplication.PresentationOptions = []
    private var escapeMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = ReviewGeometry.selectedScreen(),
              let resources = Bundle.main.resourceURL else {
            fputs("AIsland Intro Review: screen or bundled resources unavailable.\n", stderr)
            NSApp.terminate(nil)
            return
        }
        let root = resources.appendingPathComponent("prototype", isDirectory: true).standardizedFileURL
        let index = root.appendingPathComponent("index.html")
        guard FileManager.default.fileExists(atPath: index.path) else {
            fputs("AIsland Intro Review: bundled index.html missing; rebuild the reviewer.\n", stderr)
            NSApp.terminate(nil)
            return
        }
        prototypeRoot = root
        originalPresentation = NSApp.presentationOptions
        installMenu()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.userContentController.add(self, name: "reviewHost")
        installScripts(on: configuration.userContentController, screen: screen)
        let web = WKWebView(frame: screen.frame, configuration: configuration)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.autoresizingMask = [.width, .height]
        webView = web
        let reviewWindow = ReviewWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        reviewWindow.title = "AIsland Intro Review"
        reviewWindow.delegate = self
        reviewWindow.isReleasedWhenClosed = false
        reviewWindow.backgroundColor = .black
        reviewWindow.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        reviewWindow.collectionBehavior = [.fullScreenAuxiliary]
        reviewWindow.contentView = web
        reviewWindow.setFrame(screen.frame, display: false)
        window = reviewWindow
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { NSApp.terminate(nil); return nil }
            return event
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // Deny HTTP(S) and WebSocket resources, including page script requests.
        let rules = """
        [{"trigger":{"url-filter":"^(https?|wss?)://"},"action":{"type":"block"}}]
        """
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "AIslandIntroReviewNoNetwork", encodedContentRuleList: rules) { ruleList, error in
            guard let ruleList, error == nil else {
                fputs("AIsland Intro Review: network isolation rule unavailable; refusing to load.\n", stderr)
                NSApp.terminate(nil)
                return
            }
            configuration.userContentController.add(ruleList)
            web.loadFileURL(index, allowingReadAccessTo: root)
            NSApp.presentationOptions = [.hideDock, .hideMenuBar]
            reviewWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func installMenu() {
        let menu = NSMenu()
        let item = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出审阅", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
    }

    private func installScripts(on controller: WKUserContentController, screen: NSScreen) {
        controller.removeAllUserScripts()
        guard let json = try? ReviewGeometry.read(screen).json() else { return }
        let bootstrap = """
        window.AIslandReviewHost = \(json);
        document.documentElement.dataset.nativeReview = 'true';
        (() => {
          const policy = document.createElement('meta');
          policy.httpEquiv = 'Content-Security-Policy';
          policy.content = "default-src 'self' data: blob:; connect-src 'none'; frame-src 'none'; object-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; media-src 'self' data: blob:";
          let head = document.head;
          if (!head) { head = document.createElement('head'); document.documentElement.prepend(head); }
          head.appendChild(policy);
        })();
        """
        controller.addUserScript(WKUserScript(source: bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let exitButton = """
        (() => {
          document.documentElement.dataset.nativeReview = 'true';
          const exit = document.createElement('button');
          exit.id = 'native-review-exit';
          exit.textContent = '退出审阅';
          exit.setAttribute('aria-label', '退出审阅（Esc 或 Command Q）');
          exit.style.cssText = 'position:fixed;right:24px;bottom:24px;z-index:2147483647;padding:10px 16px;border:1px solid rgba(255,255,255,.3);border-radius:18px;background:rgba(12,20,42,.85);color:#fff;font:14px -apple-system,BlinkMacSystemFont,sans-serif;cursor:pointer;backdrop-filter:blur(16px)';
          exit.addEventListener('click', () => window.webkit.messageHandlers.reviewHost.postMessage('close'));
          document.body.appendChild(exit);
        })();
        """
        controller.addUserScript(WKUserScript(source: exitButton, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }

    @objc private func screenChanged() {
        guard let screen = ReviewGeometry.selectedScreen(), let webView,
              let json = try? ReviewGeometry.read(screen).json() else { return }
        window?.setFrame(screen.frame, display: true)
        installScripts(on: webView.configuration.userContentController, screen: screen)
        webView.evaluateJavaScript("window.AIslandReviewHost = \(json); window.dispatchEvent(new CustomEvent('aisland-review-geometrychange', { detail: window.AIslandReviewHost })); window.dispatchEvent(new Event('resize'));")
    }

    private func isAllowed(_ url: URL) -> Bool {
        guard url.isFileURL, let prototypeRoot else { return url.absoluteString == "about:blank" }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let root = prototypeRoot.resolvingSymlinksInPath().path
        return path == root || path.hasPrefix(root + "/")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url.map(isAllowed) == true ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "reviewHost", message.frameInfo.isMainFrame,
              message.body as? String == "close",
              let url = message.frameInfo.request.url, isAllowed(url) else { return }
        NSApp.terminate(nil)
    }

    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        NSApp.presentationOptions = originalPresentation
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        NotificationCenter.default.removeObserver(self)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "reviewHost")
    }
}

if CommandLine.arguments.contains("--geometry-json") {
    guard let screen = ReviewGeometry.selectedScreen() else {
        fputs("No screen available.\n", stderr)
        exit(1)
    }
    do { print(try ReviewGeometry.read(screen).json(pretty: true)) }
    catch { fputs("Geometry encoding failed: \(error)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = ReviewDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
