import AppKit
import Combine
import Common
import SwiftUI

@MainActor
final class WorkspacePreviewViewModel: ObservableObject {
    static let shared = WorkspacePreviewViewModel()

    @Published var workspacePreviews: [WorkspacePreview] = []
    @Published var focusedWorkspaceName: String = ""

    /// Whether the configured modifier combo is currently held down
    private(set) var modifiersAreHeld: Bool = false

    var isVisible: Bool { WorkspacePreviewPanel.shared.isShowing }

    struct WindowInfo {
        let appName: String
        let windowId: UInt32
    }

    struct ContainerInfo {
        let orientation: Orientation
        let layout: Layout
        let children: [NodeInfo]
    }

    enum NodeInfo {
        case container(ContainerInfo)
        case window(WindowInfo)
    }

    struct WorkspacePreview: Identifiable {
        let id: String
        let name: String
        let isVisible: Bool
        let isFocused: Bool
        let hasWindows: Bool
        let tilingTree: NodeInfo?
        let floatingWindowCount: Int
        let focusedWindowId: UInt32?
    }

    private init() {}

    // MARK: - Modifier key events (from GlobalObserver)

    func modifiersDidBecomeHeld() {
        guard config.workspacePreviewModifiers != nil else { return }
        modifiersAreHeld = true
        // If afterWorkspaceSwitch mode is off, show immediately
        if !config.workspacePreviewAfterWorkspaceSwitch {
            show()
        }
        // If afterWorkspaceSwitch is on, we wait for onFocusChanged() to trigger show()
    }

    func modifiersDidRelease() {
        modifiersAreHeld = false
        hide()
    }

    // MARK: - Focus change (from focus.swift)

    /// Called on any focus change (window or workspace). Only refreshes if already visible.
    func onFocusChanged() {
        if isVisible {
            updateWorkspaces()
        }
    }

    /// Called only when the focused workspace changes. Can trigger show in afterWorkspaceSwitch mode.
    func onWorkspaceChanged() {
        if isVisible {
            updateWorkspaces()
        } else if modifiersAreHeld && config.workspacePreviewAfterWorkspaceSwitch {
            show()
        }
    }

    // MARK: - Show / hide

    func show() {
        guard config.workspacePreviewModifiers != nil else { return }
        updateWorkspaces()
        WorkspacePreviewPanel.shared.show()
    }

    func hide() {
        WorkspacePreviewPanel.shared.hide()
    }

    // MARK: - Data

    func updateWorkspaces() {
        guard config.workspacePreviewModifiers != nil else {
            workspacePreviews = []
            return
        }

        let allWorkspaces = Workspace.all
        let focusedWorkspace = focus.workspace
        let focusedWindowId = focus.windowOrNil?.windowId

        focusedWorkspaceName = focusedWorkspace.name

        workspacePreviews = allWorkspaces.compactMap { workspace in
            let hasWindows = !workspace.allLeafWindowsRecursive.isEmpty
            let isFocused = workspace == focusedWorkspace

            // Always show the focused workspace even if empty.
            // Show other empty workspaces only if workspacePreviewShowEmpty is true.
            if !isFocused && !config.workspacePreviewShowEmpty && !hasWindows && !workspace.isVisible {
                return nil
            }

            let root = workspace.rootTilingContainer
            let tilingTree: NodeInfo? = root.children.isEmpty ? nil : snapshotNode(root)

            return WorkspacePreview(
                id: workspace.name,
                name: workspace.name,
                isVisible: workspace.isVisible,
                isFocused: isFocused,
                hasWindows: hasWindows,
                tilingTree: tilingTree,
                floatingWindowCount: workspace.floatingWindows.count,
                focusedWindowId: isFocused ? focusedWindowId : nil
            )
        }
    }

    // MARK: - Tree snapshot

    private func snapshotNode(_ node: TreeNode) -> NodeInfo {
        if let container = node as? TilingContainer {
            return .container(ContainerInfo(
                orientation: container.orientation,
                layout: container.layout,
                children: container.children.map { snapshotNode($0) }
            ))
        } else if let window = node as? Window {
            return .window(WindowInfo(
                appName: window.app.name ?? "Window",
                windowId: window.windowId
            ))
        } else {
            return .window(WindowInfo(appName: "Unknown", windowId: 0))
        }
    }
}
