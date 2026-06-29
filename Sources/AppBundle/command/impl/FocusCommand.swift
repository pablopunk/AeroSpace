import AppKit
import Common

struct FocusCommand: Command {
    let args: FocusCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        // todo bug: floating windows break mru
        let floatingWindows = args.floatingAsTiling ? try await makeFloatingWindowsSeenAsTiling(workspace: target.workspace) : []
        defer {
            if args.floatingAsTiling {
                restoreFloatingWindows(floatingWindows: floatingWindows, workspace: target.workspace)
            }
        }

        switch args.target {
            case .direction(let direction):
                let window = target.windowOrNil
                if let (parent, ownIndex) = window?.closestParent(hasChildrenInDirection: direction, withLayout: nil) {
                    guard let windowToFocus = parent.children[ownIndex + direction.focusOffset]
                        .findLeafWindowRecursive(snappedTo: direction.opposite) else { return false }
                    return windowToFocus.focusWindow()
                } else {
                    return hitWorkspaceBoundaries(target, io, args, direction)
                }
            case .windowId(let windowId):
                if let windowToFocus = Window.get(byId: windowId) {
                    return windowToFocus.focusWindow()
                } else {
                    return io.err("Can't find window with ID \(windowId)")
                }
            case .dfsIndex(let dfsIndex):
                if let windowToFocus = target.workspace.rootTilingContainer.allLeafWindowsRecursive.getOrNil(atIndex: Int(dfsIndex)) {
                    return windowToFocus.focusWindow()
                } else {
                    return io.err("Can't find window with DFS index \(dfsIndex)")
                }
            case .dfsRelative(let nextPrev):
                let windows = target.workspace.rootTilingContainer.allLeafWindowsRecursive
                guard let currentIndex = windows.firstIndex(where: { $0 == target.windowOrNil }) else {
                    return false
                }
                var targetIndex = switch nextPrev {
                    case .dfsNext: currentIndex + 1
                    case .dfsPrev: currentIndex - 1
                }
                if !(0 ..< windows.count).contains(targetIndex) {
                    switch args.boundariesAction {
                        case .stop: return true
                        case .fail: return false
                        case .wrapAroundTheWorkspace: targetIndex = (targetIndex + windows.count) % windows.count
                        case .wrapAroundAllMonitors: return dieT("Must be discarded by args parser")
                    }
                }
                return windows[targetIndex].focusWindow()
        }
    }
}

@MainActor private func hitWorkspaceBoundaries(
    _ target: LiveFocus,
    _ io: CmdIo,
    _ args: FocusCmdArgs,
    _ direction: CardinalDirection,
) -> Bool {
    switch args.boundaries {
        case .workspace:
            return switch args.boundariesAction {
                case .stop: true
                case .fail: false
                case .wrapAroundTheWorkspace: wrapAroundTheWorkspace(target, io, direction)
                case .wrapAroundAllMonitors: dieT("Must be discarded by args parser")
            }
        case .allMonitorsOuterFrame:
            let currentMonitor = target.workspace.workspaceMonitor
            guard let (monitors, index) = currentMonitor.findRelativeMonitor(inDirection: direction) else {
                return io.err("Should never happen. Can't find the current monitor")
            }

            if let targetMonitor = monitors.getOrNil(atIndex: index) {
                return targetMonitor.activeWorkspace.focusWorkspace()
            } else {
                guard let wrapped = monitors.get(wrappingIndex: index) else { return false }
                return hitAllMonitorsOuterFrameBoundaries(target, io, args, direction, wrapped)
            }
    }
}

@MainActor private func hitAllMonitorsOuterFrameBoundaries(
    _ target: LiveFocus,
    _ io: CmdIo,
    _ args: FocusCmdArgs,
    _ direction: CardinalDirection,
    _ wrappedMonitor: Monitor,
) -> Bool {
    // On a single-monitor setup, monitor boundaries don't make sense — there's nowhere to go.
    // Instead, navigate to the workspace in the given direction based on the keyboard layout
    // (matching the workspace overlay). This applies regardless of boundariesAction since
    // the notion of "next monitor" is meaningless with only one display.
    if sortedMonitors.count == 1,
       let targetWorkspace = findWorkspace(inDirection: direction, from: target.workspace)
    {
        return targetWorkspace.focusWorkspace()
    }
    switch args.boundariesAction {
        case .stop:
            return true
        case .fail:
            return false
        case .wrapAroundTheWorkspace:
            return wrapAroundTheWorkspace(target, io, direction)
        case .wrapAroundAllMonitors:
            wrappedMonitor.activeWorkspace.findLeafWindowRecursive(snappedTo: direction.opposite)?.markAsMostRecentChild()
            return wrappedMonitor.activeWorkspace.focusWorkspace()
    }
}

/// Keyboard-based workspace navigation grid, matching the workspace overlay layout.
private let workspaceKeyboardGrid: [[String]] = [
    ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
    ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
    ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
    ["Z", "X", "C", "V", "B", "N", "M"],
]

/// Find the workspace adjacent to the given workspace in the keyboard grid, in the given direction.
/// Returns nil if the workspace name is not on the grid or no adjacent workspace exists.
@MainActor
private func findWorkspace(inDirection direction: CardinalDirection, from workspace: Workspace) -> Workspace? {
    let upperName = workspace.name.uppercased()
    guard let (row, col) = findKeyPosition(upperName) else { return nil }
    let (newRow, newCol): (Int, Int) = switch direction {
        case .left: (row, col - 1)
        case .right: (row, col + 1)
        case .up: (row - 1, col)
        case .down: (row + 1, col)
    }
    guard let targetKey = workspaceKeyboardGrid.getOrNil(atIndex: newRow)?.getOrNil(atIndex: newCol) else {
        return nil
    }
    // Match case-insensitively to match the workspace overlay behavior.
    // If no existing workspace matches, create one with the canonical uppercase key.
    let targetWorkspace = Workspace.all.first { $0.name.uppercased() == targetKey }
        ?? Workspace.get(byName: targetKey)
    guard targetWorkspace !== workspace else { return nil }
    return targetWorkspace
}

private func findKeyPosition(_ key: String) -> (row: Int, col: Int)? {
    for (rowIndex, row) in workspaceKeyboardGrid.enumerated() {
        if let colIndex = row.firstIndex(of: key) {
            return (rowIndex, colIndex)
        }
    }
    return nil
}

@MainActor private func wrapAroundTheWorkspace(_ target: LiveFocus, _ io: CmdIo, _ direction: CardinalDirection) -> Bool {
    guard let windowToFocus = target.workspace.findLeafWindowRecursive(snappedTo: direction.opposite) else {
        return io.err(noWindowIsFocused)
    }
    return windowToFocus.focusWindow()
}

@MainActor private func makeFloatingWindowsSeenAsTiling(workspace: Workspace) async throws -> [FloatingWindowData] {
    let mruBefore = workspace.mostRecentWindowRecursive
    defer {
        mruBefore?.markAsMostRecentChild()
    }
    var _floatingWindows: [FloatingWindowData] = []
    for window in workspace.floatingWindows {
        let center = try await window.getCenter() // todo bug: we shouldn't access ax api here. What if the window was moved but it wasn't committed to ax yet?
        guard let center else { continue }

        let tilingParent: TilingContainer
        let index: Int
        if let target = center.coerce(in: workspace.workspaceMonitor.visibleRectPaddedByOuterGaps)?
            .findIn(tree: workspace.rootTilingContainer, virtual: true)
        {
            guard let targetCenter = try await target.getCenter() else { continue }
            guard let _tilingParent = target.parent as? TilingContainer else { continue }
            tilingParent = _tilingParent
            index = center.getProjection(tilingParent.orientation) >= targetCenter.getProjection(tilingParent.orientation)
                ? target.ownIndex.orDie() + 1
                : target.ownIndex.orDie()
        } else {
            index = 0
            tilingParent = workspace.rootTilingContainer
        }

        let data = window.unbindFromParent()
        let floatingWindowData = FloatingWindowData(
            window: window,
            center: center,
            parent: tilingParent,
            adaptiveWeight: data.adaptiveWeight,
            index: index,
        )
        _floatingWindows.append(floatingWindowData)
    }
    let floatingWindows: [FloatingWindowData] = _floatingWindows.sortedBy { $0.center.getProjection($0.parent.orientation) }.reversed()

    for floating in floatingWindows { // Make floating windows be seen as tiling
        floating.window.bind(to: floating.parent, adaptiveWeight: 1, index: floating.index)
    }
    return floatingWindows
}

@MainActor private func restoreFloatingWindows(floatingWindows: [FloatingWindowData], workspace: Workspace) {
    let mruBefore = workspace.mostRecentWindowRecursive
    defer {
        mruBefore?.markAsMostRecentChild()
    }
    for floating in floatingWindows {
        floating.window.bind(to: workspace, adaptiveWeight: floating.adaptiveWeight, index: INDEX_BIND_LAST)
    }
}

private struct FloatingWindowData {
    let window: Window
    let center: CGPoint

    let parent: TilingContainer
    let adaptiveWeight: CGFloat
    let index: Int
}

extension TreeNode {
    @MainActor
    func findLeafWindowRecursive(snappedTo direction: CardinalDirection) -> Window? {
        switch nodeCases {
            case .workspace(let workspace):
                return workspace.rootTilingContainer.findLeafWindowRecursive(snappedTo: direction)
            case .window(let window):
                return window
            case .tilingContainer(let container):
                if direction.orientation == container.orientation {
                    return (direction.isPositive ? container.children.last : container.children.first)?
                        .findLeafWindowRecursive(snappedTo: direction)
                } else {
                    return mostRecentChild?.findLeafWindowRecursive(snappedTo: direction)
                }
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
                die("Impossible")
        }
    }
}
