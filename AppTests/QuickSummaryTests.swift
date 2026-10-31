import AppKit
import SwiftUI
import XCTest
@testable import dev

@MainActor
final class QuickSummaryTests: XCTestCase {
    func testNotchPanelFitsNarrowScreenAndCentersOnNotch() {
        let screen = NSRect(x: 100, y: 20, width: 390, height: 844)
        let frame = NotchPanelGeometry.frame(screenFrame: screen, safeAreaTop: 38, expanded: true)

        XCTAssertEqual(frame.width, 366)
        XCTAssertEqual(frame.midX, screen.midX)
        XCTAssertEqual(frame.maxY, screen.maxY)
        XCTAssertEqual(frame.height, 288)
    }

    func testCollapsedNotchCoversCameraAreaAndKeepsSideWingsWithinDisplay() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let frame = NotchPanelGeometry.frame(screenFrame: screen, safeAreaTop: 38, physicalNotchWidth: 180, expanded: false)

        XCTAssertEqual(frame.width, 276)
        XCTAssertEqual(frame.height, 38)
        XCTAssertEqual(frame.maxY, screen.maxY)
        XCTAssertGreaterThanOrEqual(frame.minX, screen.minX)
        XCTAssertLessThanOrEqual(frame.maxX, screen.maxX)

        let narrowFrame = NotchPanelGeometry.frame(screenFrame: NSRect(x: 0, y: 0, width: 240, height: 600), safeAreaTop: 38, physicalNotchWidth: 180, expanded: false)
        XCTAssertEqual(narrowFrame.width, 216)
        XCTAssertEqual(narrowFrame.midX, 120)
    }

    func testNotchPanelCanReceiveClicksForExpandAndMinimizeControls() {
        let panel = NotchSummaryPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)

        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
    }

    func testNotchHostingViewLeavesPanelSizingToItsController() {
        let view = NotchSummaryPanel.host(Text("summary"))

        XCTAssertTrue(view.sizingOptions.isEmpty)
    }

    func testExpandedSummaryUpdatesHostedPanelAfterSwiftUIUpdate() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let store = WorkspaceStore()
        let state = NotchSummaryPanelState()
        let collapsedFrame = NotchPanelGeometry.frame(screenFrame: screen, safeAreaTop: 38, expanded: false)
        let panel = NotchSummaryPanel(contentRect: collapsedFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        defer { panel.orderOut(nil) }
        let view = NotchSummaryPanelView(store: store, state: state, safeAreaTop: 38, physicalNotchWidth: 180, summaryWidth: 440) { expanded, _ in
            panel.setFrame(NotchPanelGeometry.frame(screenFrame: screen, safeAreaTop: 38, expanded: expanded), display: true)
        }
        panel.contentView = NotchSummaryPanel.host(view)
        panel.orderFrontRegardless()

        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        state.expanded = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        XCTAssertTrue(panel.frame.height > collapsedFrame.height)
    }

    func testCommandActivityUsesOnlyExecutableLabel() {
        XCTAssertEqual(WorkspaceCommandLabel.firstToken("codex --api-key secret"), "codex")
        XCTAssertEqual(WorkspaceCommandLabel.firstToken("/usr/bin/git status"), "git")
        XCTAssertEqual(WorkspaceCommandLabel.firstToken("API_KEY=secret codex"), "Command")
        XCTAssertEqual(WorkspaceCommandLabel.firstToken("  "), "Command")
    }

    func testShellHooksDiscardAssignmentPrefixesBeforeWritingEvents() throws {
        let zsh = ShellCommandActivityMonitor { _, _ in }
        let (_, zshEnvironment) = zsh.launchConfiguration(shellPath: "/bin/zsh")
        defer { zsh.stop() }
        let zshRoot = try XCTUnwrap(zshEnvironment.first(where: { $0.hasPrefix("ZDOTDIR=") })).dropFirst("ZDOTDIR=".count)
        let zshrc = try String(contentsOf: URL(fileURLWithPath: String(zshRoot)).appending(path: ".zshrc"), encoding: .utf8)
        XCTAssertTrue(zshrc.contains("__dev_summary_command='Command'"))

        let bash = ShellCommandActivityMonitor { _, _ in }
        let (bashArguments, _) = bash.launchConfiguration(shellPath: "/bin/bash")
        defer { bash.stop() }
        let rcIndex = try XCTUnwrap(bashArguments.firstIndex(of: "--rcfile"))
        let bashrc = try String(contentsOfFile: bashArguments[rcIndex + 1], encoding: .utf8)
        XCTAssertTrue(bashrc.contains("label=\"Command\""))

        let fish = ShellCommandActivityMonitor { _, _ in }
        let (fishArguments, _) = fish.launchConfiguration(shellPath: "/opt/homebrew/bin/fish")
        defer { fish.stop() }
        XCTAssertTrue(fishArguments.last?.contains("set label Command") == true)
    }

    func testShellActivityRecordDecodesCommandAndExitCode() {
        let record = ShellCommandActivityMonitor.parseEventLine(Data("Z2l0\t7".utf8))

        XCTAssertEqual(record?.command, "git")
        XCTAssertEqual(record?.exitCode, 7)
        XCTAssertNil(ShellCommandActivityMonitor.parseEventLine(Data("not-base64\tnope".utf8)))
    }
}
