import AppKit
import SwiftUI

@MainActor
final class WorkspacePreviewPanel: NSPanelHud {
    private let monitorId: Int

    init(monitor: WorkspacePreviewViewModel.MonitorPreview) {
        self.monitorId = monitor.id
        super.init()
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        update(monitor: monitor)
    }

    func update(monitor: WorkspacePreviewViewModel.MonitorPreview) {
        self.contentView = NSHostingView(rootView: WorkspacePreviewView(monitor: monitor))
        if let hostingView = self.contentView as? NSHostingView<WorkspacePreviewView> {
            setContentSize(hostingView.fittingSize)
        }
        centerOnScreen()
    }

    private func centerOnScreen() {
        let screen = NSScreen.screens.getOrNil(atIndex: monitorId - 1)
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        guard let visibleFrame else { return }
        let panelSize = self.frame.size
        let x = visibleFrame.midX - panelSize.width / 2
        let y = visibleFrame.midY - panelSize.height / 2
        self.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
final class WorkspacePreviewPanelsController {
    static let shared = WorkspacePreviewPanelsController()

    private var panels: [Int: WorkspacePreviewPanel] = [:]

    var isShowing: Bool { panels.values.contains(where: \.isVisible) }

    private init() {}

    func show(monitors: [WorkspacePreviewViewModel.MonitorPreview]) {
        let visibleIds = Set(monitors.map(\.id))

        for monitor in monitors {
            let panel = panels[monitor.id] ?? WorkspacePreviewPanel(monitor: monitor)
            panel.update(monitor: monitor)
            panel.orderFrontRegardless()
            panels[monitor.id] = panel
        }

        for (id, panel) in panels where !visibleIds.contains(id) {
            panel.orderOut(nil)
        }
    }

    func hide() {
        for panel in panels.values {
            panel.orderOut(nil)
        }
    }
}
