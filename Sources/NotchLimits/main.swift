import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        enableLaunchAtLoginOnce()
        store.start()
        notch = NotchController(store: store)
        notch?.start()
    }

    /// Opt in once on first launch; later the user controls it from the right-click menu.
    private func enableLaunchAtLoginOnce() {
        let key = "didOfferLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key), Bundle.main.bundlePath.hasSuffix(".app") else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
