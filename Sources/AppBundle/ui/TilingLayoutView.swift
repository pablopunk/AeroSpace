import SwiftUI
import Common

struct TilingLayoutView: View {
    let tilingTree: WorkspacePreviewViewModel.NodeInfo?
    let floatingWindowCount: Int
    let focusedWindowId: UInt32?

    var body: some View {
        GeometryReader { _ in
            if let tree = tilingTree {
                NodeView(node: tree, focusedWindowId: focusedWindowId)
            } else if floatingWindowCount > 0 {
                Text("\(floatingWindowCount) floating")
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(3)
            } else {
                Text("Empty")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(3)
            }
        }
    }
}

struct NodeView: View {
    let node: WorkspacePreviewViewModel.NodeInfo
    let focusedWindowId: UInt32?

    var body: some View {
        switch node {
        case .window(let info):
            WindowTileView(appName: info.appName, isFocused: info.windowId == focusedWindowId && focusedWindowId != nil)
        case .container(let info):
            ContainerView(container: info, focusedWindowId: focusedWindowId)
        }
    }
}

struct WindowTileView: View {
    let appName: String
    let isFocused: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(isFocused ? Color.blue.opacity(0.5) : Color.blue.opacity(0.25))
            if isFocused {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.primary.opacity(0.5), lineWidth: 1)
            }
            Text(appName.prefix(12))
                .font(.system(size: 7))
                .lineLimit(1)
                .foregroundColor(isFocused ? .primary : .secondary)
        }
    }
}

struct ContainerView: View {
    let container: WorkspacePreviewViewModel.ContainerInfo
    let focusedWindowId: UInt32?

    var body: some View {
        if container.children.isEmpty {
            Color.clear
        } else if container.orientation == .h {
            // .h = windows placed along horizontal axis = side by side
            HStack(spacing: 1) {
                ForEach(Array(container.children.enumerated()), id: \.offset) { _, child in
                    NodeView(node: child, focusedWindowId: focusedWindowId)
                }
            }
        } else {
            // .v = windows placed along vertical axis = stacked
            VStack(spacing: 1) {
                ForEach(Array(container.children.enumerated()), id: \.offset) { _, child in
                    NodeView(node: child, focusedWindowId: focusedWindowId)
                }
            }
        }
    }
}
