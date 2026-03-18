import SwiftUI
import Common

struct WorkspacePreviewView: View {
    @ObservedObject var viewModel = WorkspacePreviewViewModel.shared

    // Keyboard layout mapping (QWERTY)
    private let keyboardRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"],
    ]

    var body: some View {
        VStack(spacing: 8) {
            // Only show rows that have at least one workspace
            ForEach(0..<keyboardRows.count, id: \.self) { rowIndex in
                let row = keyboardRows[rowIndex]
                let rowHasWorkspace = row.contains { workspaceForKey($0) != nil }
                if rowHasWorkspace {
                    HStack(spacing: 6) {
                        ForEach(0..<row.count, id: \.self) { colIndex in
                            let key = row[colIndex]
                            if let workspace = workspaceForKey(key) {
                                WorkspaceCell(
                                    workspace: workspace,
                                    keyLabel: key
                                )
                            }
                        }
                    }
                }
            }

            // Overflow workspaces (non-keyboard-matched)
            let overflowWorkspaces = viewModel.workspacePreviews.filter { !isKeyMapped($0.name) }
            if !overflowWorkspaces.isEmpty {
                Divider().padding(.horizontal)
                HStack(spacing: 6) {
                    ForEach(overflowWorkspaces) { workspace in
                        WorkspaceCell(
                            workspace: workspace,
                            keyLabel: nil
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(
            VisualEffectBlur(
                material: .hudWindow,
                blendingMode: .behindWindow
            )
        )
        .cornerRadius(12)
    }

    private func workspaceForKey(_ key: String) -> WorkspacePreviewViewModel.WorkspacePreview? {
        viewModel.workspacePreviews.first { $0.name.uppercased() == key.uppercased() }
    }

    private func isKeyMapped(_ name: String) -> Bool {
        let allKeys = keyboardRows.flatMap { $0 }
        return allKeys.contains { $0.uppercased() == name.uppercased() }
    }
}

struct WorkspaceCell: View {
    let workspace: WorkspacePreviewViewModel.WorkspacePreview
    let keyLabel: String?

    var body: some View {
        VStack(spacing: 4) {
            // Header
            HStack(spacing: 4) {
                if let keyLabel = keyLabel {
                    Text(keyLabel)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 14)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(3)
                }
                Spacer()
                if workspace.isVisible {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                }
            }

            // Mini tiling layout preview
            TilingLayoutView(
                tilingTree: workspace.tilingTree,
                floatingWindowCount: workspace.floatingWindowCount,
                focusedWindowId: workspace.focusedWindowId
            )
            .frame(height: 50)
            .cornerRadius(3)
        }
        .padding(6)
        .frame(width: 100)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(workspace.isFocused ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(workspace.isFocused ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            Task { @MainActor in
                let ws = Workspace.get(byName: workspace.name)
                _ = ws.focusWorkspace()
                WorkspacePreviewViewModel.shared.hide()
            }
        }
    }
}

// Visual effect blur wrapper
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}