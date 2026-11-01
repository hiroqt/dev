import AppKit
import SwiftUI

extension View {
    func dismissOnOutsideClick() -> some View {
        modifier(OutsideClickDismissal())
    }
}

private struct OutsideClickDismissal: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.background(SheetOutsideClickObserver(dismiss: { dismiss() }))
    }
}

private struct SheetOutsideClickObserver: NSViewRepresentable {
    let dismiss: () -> Void

    func makeNSView(context: Context) -> ObserverView {
        ObserverView(dismiss: dismiss)
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.dismiss = dismiss
    }

    static func dismantleNSView(_ view: ObserverView, coordinator: ()) {
        view.stopObserving()
    }

    final class ObserverView: NSView {
        var dismiss: () -> Void
        private var monitor: Any?

        init(dismiss: @escaping () -> Void) {
            self.dismiss = dismiss
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let sheet = self.window,
                      let parent = sheet.sheetParent, event.window === parent,
                      sheet.attachedSheet == nil,
                      NSApp.modalWindow == nil || NSApp.modalWindow === sheet else { return event }
                self.dismiss()
                return nil
            }
        }

        func stopObserving() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
