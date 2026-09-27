import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class NotchModel {
    var isExpanded = false
    var notchSize = CGSize(width: 190, height: 32)
    let store: UsageStore

    static let width: CGFloat = 500
    static let maxHeight: CGFloat = 330

    init(store: UsageStore) {
        self.store = store
    }

    /// Grows with the tallest card: rows of usage plus an error line.
    var expandedSize: CGSize {
        let cards = store.visible.map { _, status -> CGFloat in
            let rows = CGFloat(max(status.snapshot?.windows.count ?? 2, 1))
            let error: CGFloat = if case .failed = status { 24 } else { 0 }
            return 12 + 20 + 10 + rows * 36 + (rows - 1) * 10 + error + 12
        }
        let card = cards.max() ?? 90
        return CGSize(width: Self.width, height: min(Self.maxHeight, notchSize.height + 10 + card + 14))
    }
}

/// Owns a transparent panel pinned over the notch. The panel ignores the
/// mouse while collapsed, so it never steals clicks from the menu bar.
@MainActor
final class NotchController {
    private let model: NotchModel
    private let store: UsageStore
    private var panel: NSPanel!
    private var monitors: [Any] = []
    private var collapseWork: DispatchWorkItem?

    /// Extra room around the panel for the drop shadow.
    private let shadowMargin: CGFloat = 30

    init(store: UsageStore) {
        self.store = store
        self.model = NotchModel(store: store)
    }

    func start() {
        let root = NotchView(model: model, store: store)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []

        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar + 1
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.contentView = hosting
        layout()
        panel.orderFrontRegardless()
        if pinned { setExpanded(true) }

        let handler: (NSEvent) -> Void = { [weak self] _ in self?.mouseMoved() }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.layout() }
        }
    }

    private var screen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func layout() {
        let screen = screen
        let frame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            model.notchSize = CGSize(width: frame.width - left.width - right.width,
                                     height: screen.safeAreaInsets.top)
        } else {
            // No notch: pretend there is one in the middle of the menu bar.
            model.notchSize = CGSize(width: 190, height: NSStatusBar.system.thickness)
        }
        let size = CGSize(width: NotchModel.width + shadowMargin * 2,
                          height: NotchModel.maxHeight + shadowMargin)
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    /// Hot zone in screen coordinates: the notch while collapsed, the panel while open.
    private var hotZone: NSRect {
        let frame = screen.frame
        let size = model.isExpanded
            ? model.expandedSize
            : CGSize(width: model.notchSize.width + 16, height: model.notchSize.height)
        return NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height,
                      width: size.width, height: size.height + 1)
    }

    /// NOTCH_LIMITS_PINNED=1 keeps the panel open (screenshots, UI work).
    private let pinned = ProcessInfo.processInfo.environment["NOTCH_LIMITS_PINNED"] == "1"

    private func mouseMoved() {
        guard !pinned else { return }
        if hotZone.contains(NSEvent.mouseLocation) {
            collapseWork?.cancel()
            collapseWork = nil
            if !model.isExpanded { setExpanded(true) }
        } else if model.isExpanded, collapseWork == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.collapseWork = nil
                if !self.hotZone.contains(NSEvent.mouseLocation) { self.setExpanded(false) }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    private func setExpanded(_ expanded: Bool) {
        if expanded { store.refreshIfStale() }
        withAnimation(expanded
            ? .spring(response: 0.42, dampingFraction: 0.74)
            : .spring(response: 0.34, dampingFraction: 0.9)) {
            model.isExpanded = expanded
        }
        panel.ignoresMouseEvents = !expanded
    }
}
