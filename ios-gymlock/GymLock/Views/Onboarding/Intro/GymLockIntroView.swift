//
//  GymLockIntroView.swift
//  GymLock
//
//  Full-screen "tap to break the chains" intro.
//  Renders the bundled GymLockIntro.html (the exact approved animation) in a WKWebView
//  and plays native Core Haptics for every moment of it. Follows light/dark mode live and
//  adapts to every screen size (iPhone SE → Pro Max → iPad) on its own.
//
//  Usage:
//      GymLockIntroView(variant: .classic) { /* finished → go to next onboarding step */ }
//
//  DO NOT re-implement the animation in SwiftUI — this wrapper is the integration.
//

import SwiftUI
import WebKit

enum GymLockIntroVariant: String {
    /// V1 — logo wrapped in chains on a clean background
    case classic
    /// V2 — same, over a wall of distracting app icons that crack and shatter
    case apps
}

struct GymLockIntroView: View {
    let variant: GymLockIntroVariant
    /// Called once the reveal + tagline have settled (~3.7 s after the chains break).
    var onFinished: () -> Void = {}
    /// Called if the user taps the screen after `onFinished` (optional "tap to continue").
    var onContinue: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme

    /// Background colours match the animation's own backgrounds exactly (no flash while loading).
    static let darkBackground = Color.black
    static let lightBackground = Color(red: 238 / 255, green: 238 / 255, blue: 241 / 255)

    var body: some View {
        GymLockIntroWebView(
            variant: variant,
            theme: colorScheme == .dark ? "dark" : "light",
            onEvent: handle
        )
        .background(colorScheme == .dark ? Self.darkBackground : Self.lightBackground)
        .ignoresSafeArea()          // edge to edge — the animation fits itself to the screen
        .statusBarHidden(true)
        .onAppear { IntroHaptics.shared.prepare() }
        .onDisappear { IntroHaptics.shared.shutdown() }
    }

    private func handle(_ type: String, _ body: [String: Any]) {
        let haptics = IntroHaptics.shared
        switch type {
        case "notify":   haptics.notificationStorm()          // V2: app wall pops in with badges
        case "land":     haptics.land()                       // V2: chained logo drops in
        case "tap":
            let count = body["count"] as? Int ?? 1
            if count < 5 { haptics.tap(level: count) }        // 5th tap is the break (below)
        case "break":    haptics.chainBreak()                 // chains snap
        case "slam":     haptics.slam()                       // tagline stomps down
        case "finished": onFinished()
        case "continue": onContinue()
        default: break
        }
    }

    /// Optional: call once early (e.g. in the App's init or the onboarding root's `.task`)
    /// so WebKit's process is already warm when the intro appears.
    @MainActor static func prewarm() {
        GymLockIntroWebView.prewarm()
    }
}

// MARK: - WKWebView host

struct GymLockIntroWebView: UIViewRepresentable {
    let variant: GymLockIntroVariant
    let theme: String
    let onEvent: (String, [String: Any]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEvent: onEvent) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        // Config is injected before the page runs → app mode (full screen, no preview controls).
        let config = "window.GYMLOCK_CONFIG = {variant: '\(variant.rawValue)', theme: '\(theme)'};"
        controller.addUserScript(WKUserScript(source: config, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.add(WeakScriptMessageHandler(context.coordinator), name: "gymlock")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.suppressesIncrementalRendering = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.alwaysBounceVertical = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.pinchGestureRecognizer?.isEnabled = false
        web.scrollView.showsVerticalScrollIndicator = false
        web.scrollView.showsHorizontalScrollIndicator = false
        web.allowsLinkPreview = false
        web.allowsBackForwardNavigationGestures = false

        context.coordinator.lastTheme = theme
        Self.loadIntro(into: web)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.onEvent = onEvent
        if context.coordinator.lastTheme != theme {
            context.coordinator.lastTheme = theme
            web.evaluateJavaScript("window.GymLockIntro && window.GymLockIntro.setTheme('\(theme)')", completionHandler: nil)
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "gymlock")
        web.stopLoading()
    }

    /// Loads GymLockIntro.html from the app bundle (preferred) or from an asset-catalog
    /// Data Set named "GymLockIntro" (fallback if loose resource files can't be added).
    private static func loadIntro(into web: WKWebView) {
        if let url = Bundle.main.url(forResource: "GymLockIntro", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else if let asset = NSDataAsset(name: "GymLockIntro"),
                  let html = String(data: asset.data, encoding: .utf8) {
            web.loadHTMLString(html, baseURL: nil)
        } else {
            assertionFailure("GymLockIntro.html is missing — add it to the app target (Copy Bundle Resources).")
        }
    }

    @MainActor private static var warmView: WKWebView?
    @MainActor static func prewarm() {
        guard GymLockIntroWebView.warmView == nil else { return }
        let web = WKWebView(frame: .zero)
        web.loadHTMLString("<html></html>", baseURL: nil)
        GymLockIntroWebView.warmView = web
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            GymLockIntroWebView.warmView = nil
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        var onEvent: (String, [String: Any]) -> Void
        var lastTheme = ""

        init(onEvent: @escaping (String, [String: Any]) -> Void) {
            self.onEvent = onEvent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            onEvent(type, body)
        }
    }
}

/// Avoids the retain cycle WKUserContentController creates with its message handlers.
@MainActor
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
