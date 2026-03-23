import SwiftUI
import Common

struct WorkspacePreviewView: View {
    let monitor: WorkspacePreviewViewModel.MonitorPreview
    private let columnSpacing: CGFloat = 10
    private let rowSpacing: CGFloat = 14

    private let keyboardRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"],
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(monitor.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if monitor.isFocused {
                    Circle()
                        .fill(Color.accentColor.opacity(0.9))
                        .frame(width: 8, height: 8)
                }
            }

            VStack(alignment: .leading, spacing: rowSpacing) {
                ForEach(0..<keyboardRows.count, id: \.self) { rowIndex in
                    let row = keyboardRows[rowIndex]
                    let rowWorkspaces = row.compactMap(workspaceForKey)
                    if !rowWorkspaces.isEmpty {
                        HStack(spacing: columnSpacing) {
                            ForEach(rowWorkspaces) { workspace in
                                WorkspaceCell(workspace: workspace)
                            }
                        }
                    }
                }

                let overflowWorkspaces = monitor.workspaces.filter { !isKeyMapped($0.name) }
                if !overflowWorkspaces.isEmpty {
                    Divider()
                        .overlay(Color.white.opacity(0.08))
                    HStack(spacing: columnSpacing) {
                        ForEach(overflowWorkspaces) { workspace in
                            WorkspaceCell(workspace: workspace)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            VisualEffectBlur(
                material: .hudWindow,
                blendingMode: .behindWindow
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(monitor.isFocused ? Color.accentColor.opacity(0.75) : Color.white.opacity(0.08), lineWidth: monitor.isFocused ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func workspaceForKey(_ key: String) -> WorkspacePreviewViewModel.WorkspacePreview? {
        monitor.workspaces.first { $0.name.uppercased() == key.uppercased() }
    }

    private func isKeyMapped(_ name: String) -> Bool {
        keyboardRows.flatMap { $0 }.contains { $0.uppercased() == name.uppercased() }
    }
}

private struct WorkspaceCell: View {
    let workspace: WorkspacePreviewViewModel.WorkspacePreview

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Text(workspace.name)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if workspace.isVisible {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
            }

            TilingLayoutView(
                tilingTree: workspace.tilingTree,
                floatingWindowCount: workspace.floatingWindowCount,
                focusedWindowId: workspace.focusedWindowId
            )
            .frame(height: 44)
            .cornerRadius(4)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(workspace.isFocused ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(workspace.isFocused ? Color.accentColor : Color.clear, lineWidth: 1.25)
        )
        .frame(width: 96, height: 74)
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
