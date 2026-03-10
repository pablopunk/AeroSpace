@testable import AppBundle
import XCTest

@MainActor
final class TreeNodeTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testChildParentCyclicReferenceMemoryLeak() {
        let workspace = Workspace.get(byName: name) // Don't cache root node
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

        XCTAssertTrue(window.parent != nil)
        workspace.rootTilingContainer.unbindFromParent()
        XCTAssertTrue(window.parent == nil)
    }

    func testIsEffectivelyEmpty() {
        let workspace = Workspace.get(byName: name)

        XCTAssertTrue(workspace.isEffectivelyEmpty)
        weak var window: TestWindow? = .new(id: 1, parent: workspace.rootTilingContainer)
        XCTAssertNotEqual(window, nil)
        XCTAssertTrue(!workspace.isEffectivelyEmpty)
        window!.unbindFromParent()
        XCTAssertTrue(workspace.isEffectivelyEmpty)

        // Don't save to local variable
        TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        XCTAssertTrue(!workspace.isEffectivelyEmpty)
    }

    func testNormalizeContainers_dontRemoveRoot() {
        let workspace = Workspace.get(byName: name)
        weak var root = workspace.rootTilingContainer
        func test() {
            XCTAssertNotEqual(root, nil)
            XCTAssertTrue(root!.isEffectivelyEmpty)
            workspace.normalizeContainers()
            XCTAssertNotEqual(root, nil)
        }
        test()

        config.enableNormalizationFlattenContainers = true
        test()
    }

    func testNormalizeContainers_singleWindowChild() {
        config.enableNormalizationFlattenContainers = true
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: 0, parent: $0)
            TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 1, parent: $0)
            }
        }
        workspace.normalizeContainers()
        assertEquals(
            .h_tiles([.window(0), .window(1)]),
            workspace.rootTilingContainer.layoutDescription,
        )
    }

    func testNormalizeContainers_removeEffectivelyEmpty() {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                _ = TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1)
            }
        }
        assertEquals(workspace.rootTilingContainer.children.count, 1)
        workspace.normalizeContainers()
        assertEquals(workspace.rootTilingContainer.children.count, 0)
    }

    func testNormalizeContainers_flattenContainers() {
        let workspace = Workspace.get(byName: name) // Don't cache root node
        workspace.rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 1, parent: $0, adaptiveWeight: 1)
            }
        }
        workspace.normalizeContainers()
        XCTAssertTrue(workspace.rootTilingContainer.children.singleOrNil() is TilingContainer)

        config.enableNormalizationFlattenContainers = true
        workspace.normalizeContainers()
        XCTAssertTrue(workspace.rootTilingContainer.children.singleOrNil() is TestWindow)
    }

    func testBspInsertionSplitsFocusedTilingWindow() async throws {
        config.windowInsertionPolicy = .bsp
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }
        let window3 = TestWindow.new(id: 3, parent: workspace)

        try await window3.relayoutWindow(on: workspace, forceTile: true)

        assertEquals(
            workspace.rootTilingContainer.layoutDescription,
            .h_tiles([.h_tiles([.window(1), .window(3)]), .window(2)]),
        )
    }

    func testBspFirstSplitUsesRootOrientation() async throws {
        config.windowInsertionPolicy = .bsp
        let workspace = Workspace.get(byName: name)
        let window1 = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(window1.focusWindow(), true)
        let window2 = TestWindow.new(id: 2, parent: workspace)

        try await window2.relayoutWindow(on: workspace, forceTile: true)

        assertEquals(
            workspace.rootTilingContainer.layoutDescription,
            .h_tiles([.h_tiles([.window(1), .window(2)])]),
        )
    }

    func testBspFloatAfterSplitsKeepsDeepSplitFloating() async throws {
        config.windowInsertionPolicy = .bsp
        config.bspFloatAfterSplits = 2
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
        }
        let window3 = TestWindow.new(id: 3, parent: workspace)
        try await window3.relayoutWindow(on: workspace, forceTile: true)

        assertEquals(window3.focusWindow(), true)
        let window4 = TestWindow.new(id: 4, parent: workspace)

        try await window4.relayoutWindow(on: workspace, forceTile: true)

        assertEquals(
            workspace.layoutDescription,
            .workspace([.h_tiles([.window(1), .h_tiles([.window(2), .window(3)])]), .window(4)]),
        )
    }

    func testBspFloatAfterSplitsStillAllowsShallowFocusedSplit() async throws {
        config.windowInsertionPolicy = .bsp
        config.bspFloatAfterSplits = 2
        let workspace = Workspace.get(byName: name)
        var window1: TestWindow!
        workspace.rootTilingContainer.apply {
            window1 = TestWindow.new(id: 1, parent: $0)
            assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
        }
        let window3 = TestWindow.new(id: 3, parent: workspace)

        try await window3.relayoutWindow(on: workspace, forceTile: true)

        assertEquals(window3.focusWindow(), true)
        let window4 = TestWindow.new(id: 4, parent: workspace)

        try await window4.relayoutWindow(on: workspace, forceTile: true)

        assertEquals(window1.focusWindow(), true)
        let window5 = TestWindow.new(id: 5, parent: workspace)

        try await window5.relayoutWindow(on: workspace, forceTile: true)

        assertEquals(
            workspace.layoutDescription,
            .workspace([.h_tiles([.h_tiles([.window(1), .window(5)]), .h_tiles([.window(2), .window(3)])]), .window(4)]),
        )
    }

    func testAccordionIgnoresBspInsertion() async throws {
        config.windowInsertionPolicy = .bsp
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.layout = .accordion
        workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }
        let window3 = TestWindow.new(id: 3, parent: workspace)

        try await window3.relayoutWindow(on: workspace, forceTile: true)

        assertEquals(
            workspace.rootTilingContainer.layoutDescription,
            .h_accordion([.window(1), .window(2), .window(3)]),
        )
    }

    func testAccordionIgnoresBspFloatAfterSplits() async throws {
        config.windowInsertionPolicy = .bsp
        config.bspFloatAfterSplits = 1
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.layout = .accordion
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TestWindow.new(id: 2, parent: $0)
        }
        let window3 = TestWindow.new(id: 3, parent: workspace)

        try await window3.relayoutWindow(on: workspace, forceTile: true)

        assertEquals(
            workspace.rootTilingContainer.layoutDescription,
            .h_accordion([.window(1), .window(2), .window(3)]),
        )
    }
}
