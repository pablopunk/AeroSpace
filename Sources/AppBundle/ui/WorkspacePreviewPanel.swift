import AppKit
import SwiftUI

@MainActor
final class WorkspacePreviewPanel: NSPanelHud {
    static let shared = WorkspacePreviewPanel()

    var isShowing: Bool { isVisible }

    override private init() {
        super.init()

        let hostingView = NSHostingView(rootView: WorkspacePreviewView())
        self.contentView = hostingView
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
    }

    func show() {
        guard config.workspacePreviewModifiers != nil else { return }

        // Size to fit content, then center on screen
        if let hostingView = self.contentView as? NSHostingView<WorkspacePreviewView> {
            let fittingSize = hostingView.fittingSize
            setContentSize(fittingSize)
        }
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let panelSize = self.frame.size
            let x = screenRect.midX - panelSize.width / 2
            let y = screenRect.midY - panelSize.height / 2
            self.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.orderFrontRegardless()
    }

    func hide() {
        self.orderOut(nil)
    }
}
