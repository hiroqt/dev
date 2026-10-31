import AppKit
import Observation
import SwiftUI
import SwiftTerm

@MainActor
enum WorkspaceWindowActivation {
    static func show(openWindow: () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { !($0 is NSPanel) }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow()
        }
    }
}

struct QuickSummaryView: View {
    @Bindable var store: WorkspaceStore
    let activate: (WorkspaceQuickAction) -> Void
    var summaryWidth: CGFloat = 360
    var showsShortcuts = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("dev", systemImage: "waveform.path.ecg").font(.headline)
                Spacer()
                Button("Open Workspace") { open(.workspace) }
                    .buttonStyle(.borderedProminent)
            }
            if store.repositories.isEmpty {
                Text("Connect GitHub to see project activity.").foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Open pull requests").foregroundStyle(.secondary)
                    Spacer()
                    Text(store.openPullRequestCounts.values.reduce(0, +).formatted()).fontWeight(.semibold)
                }
                ForEach(store.repositories
                    .sorted { (store.openPullRequestCounts[$0.id] ?? 0) > (store.openPullRequestCounts[$1.id] ?? 0) }
                    .filter { (store.openPullRequestCounts[$0.id] ?? 0) > 0 }
                    .prefix(3)) { repository in
                    HStack {
                        Text(repository.name).lineLimit(1)
                        Spacer()
                        Text((store.openPullRequestCounts[repository.id] ?? 0).formatted())
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                ForEach(store.overviewPullRequests.prefix(3)) { item in
                    Link(destination: item.request.htmlURL) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(item.repository.name) · #\(item.request.number)").font(.caption).foregroundStyle(.secondary)
                            Text(item.request.title).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let event = store.summaryEvents.first {
                Divider()
                let text = event.kind == .pullRequest ? "\(event.title): \(event.detail)" : "\(event.title) · \(event.detail)"
                Group {
                    if let url = event.url {
                        Link(destination: url) { Label(text, systemImage: "arrow.triangle.pull") }
                    } else {
                        Label(text, systemImage: "terminal")
                    }
                }
                .lineLimit(1)
                .transition(reduceMotion ? .identity : .move(edge: .top).combined(with: .opacity))
                .accessibilityIdentifier("summary-latest-event")
            }
            Divider()
            if showsShortcuts {
                HStack(spacing: 8) {
                    shortcut("Workspace", icon: "square.grid.2x2") { open(.workspace) }
                    shortcut("Skills", icon: "sparkles.rectangle.stack") { open(.skills) }
                    shortcut("Terminal", icon: "terminal") { open(.terminal) }
                    shortcut("Codex", icon: "sparkles") { open(.codex) }
                }
            }
            HStack {
                Label("AI usage preview", systemImage: "chart.bar.xaxis").foregroundStyle(.secondary)
                Spacer()
                Text("Coming soon").font(.caption).foregroundStyle(.tertiary)
            }
            .accessibilityIdentifier("summary-ai-coming-soon")
            HStack {
                Label("Tasks", systemImage: "checklist").foregroundStyle(.secondary)
                Spacer()
                Text("Coming soon").font(.caption).foregroundStyle(.tertiary)
            }
            .accessibilityIdentifier("summary-tasks-coming-soon")
        }
        .padding(16)
        .frame(width: summaryWidth)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: store.summaryEvents.first?.id)
    }

    private func shortcut(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).labelStyle(.titleAndIcon).font(.caption)
        }
        .buttonStyle(.bordered)
        .help(title)
    }

    private func open(_ action: WorkspaceQuickAction) {
        activate(action)
    }
}

@MainActor
@Observable
final class NotchSummaryPanelState {
    var expanded = false
}

struct NotchSummaryPanelView: View {
    @Bindable var store: WorkspaceStore
    @Bindable var state: NotchSummaryPanelState
    let safeAreaTop: CGFloat
    let physicalNotchWidth: CGFloat
    let summaryWidth: CGFloat
    let resize: (Bool, Bool) -> Void
    @State private var hovered = false
    @State private var selectedTool: WorkspaceQuickAction = .workspace
    @State private var terminalStarted = false
    @State private var codexStarted = false
    @State private var skillSearch = ""
    @AppStorage("workspaceBackgroundTheme") private var themeRaw = WorkspaceBackgroundTheme.pixelMosaic.rawValue
    @AppStorage("workspacePixelMosaicPalette") private var pixelPalette = WorkspaceThemePalette.aqua.rawValue
    @AppStorage("workspaceTerminalStreamPalette") private var terminalPalette = WorkspaceThemePalette.emerald.rawValue
    @AppStorage("workspaceAuroraGridPalette") private var auroraPalette = WorkspaceThemePalette.aqua.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: WorkspaceBackgroundTheme { WorkspaceBackgroundTheme(rawValue: themeRaw) ?? .pixelMosaic }
    private var palette: WorkspaceThemePalette {
        let raw = switch theme {
        case .pixelMosaic: pixelPalette
        case .terminalStream: terminalPalette
        case .auroraGrid: auroraPalette
        }
        return WorkspaceThemePalette(rawValue: raw) ?? .aqua
    }

    var body: some View {
        GeometryReader { viewport in
        VStack(spacing: 10) {
            // Retained tool sessions must not impose their minimum width on the idle cap.
            ZStack {
                    VStack(spacing: 0) {
                        // Keep the camera's entire safe-area strip free of summary text.
                        HStack {
                            Spacer()
                            Button { state.expanded = false } label: {
                                Image(systemName: "chevron.up").frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Minimize summary to notch")
                        }
                        .padding(.horizontal, 28)
                        .frame(height: safeAreaTop)
                        ZStack {
                            ScrollView {
                                QuickSummaryView(store: store, activate: open, summaryWidth: summaryWidth, showsShortcuts: false)
                                    .frame(maxWidth: .infinity)
                            }
                            .scrollIndicators(.hidden)
                            .opacity(selectedTool == .workspace ? 1 : 0)
                            .allowsHitTesting(selectedTool == .workspace)
                            .accessibilityHidden(selectedTool != .workspace)
                            if selectedTool == .skills { skillsPreview }
                            if terminalStarted {
                                EmbeddedTerminalTab(store: store, directory: nil, initialCommand: nil)
                                    .opacity(selectedTool == .terminal ? 1 : 0)
                                    .allowsHitTesting(selectedTool == .terminal)
                                    .accessibilityHidden(selectedTool != .terminal)
                                    .accessibilityIdentifier("notch-terminal")
                            }
                            if codexStarted {
                                EmbeddedTerminalTab(store: store, directory: nil, initialCommand: "codex")
                                    .opacity(selectedTool == .codex ? 1 : 0)
                                    .allowsHitTesting(selectedTool == .codex)
                                    .accessibilityHidden(selectedTool != .codex)
                                    .accessibilityIdentifier("notch-codex")
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    }
                    .frame(width: viewport.size.width, height: max(1, viewport.size.height - (state.expanded ? 50 : 0)), alignment: .top)
                    .opacity(state.expanded ? 1 : 0)
                    .allowsHitTesting(state.expanded)
                    .accessibilityHidden(!state.expanded)
                if !state.expanded {
                    Button { state.expanded = true } label: {
                        HStack(spacing: 0) {
                            Text("dev").font(.system(size: 10, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                            Color.clear.frame(width: physicalNotchWidth + 8)
                            HStack(spacing: 4) {
                                Text(store.openPullRequestCounts.values.reduce(0, +).formatted()).monospacedDigit()
                                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(.white.opacity(hovered ? 1 : 0.8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: viewport.size.width, height: viewport.size.height)
                    .onHover { hovered = $0 }
                    .accessibilityLabel("Open project summary")
                }
            }
            .background {
                Color.black
                if state.expanded {
                    VStack(spacing: 0) {
                        Color.black.frame(height: safeAreaTop)
                        WorkspaceThemeBackdrop(theme: theme, palette: palette, reduceMotion: reduceMotion)
                            .overlay(Color.black.opacity(0.55))
                            .clipped()
                    }
                }
            }
            .clipShape(NotchCapShape())

            if state.expanded {
                HStack(spacing: 10) {
                    HStack(spacing: 2) {
                        widget("Workspace", icon: "square.grid.2x2", action: .workspace)
                        widget("Skills", icon: "sparkles.rectangle.stack", action: .skills)
                    }
                    .padding(.horizontal, 6).background(.black, in: Capsule())
                    HStack(spacing: 2) {
                        widget("Terminal", icon: "terminal", action: .terminal)
                        widget("Codex", icon: "sparkles", action: .codex)
                    }
                    .padding(.horizontal, 6).background(.black, in: Capsule())
                }
                .frame(height: 32)
                .padding(.bottom, 8)
            }
        }
        .frame(width: viewport.size.width, height: viewport.size.height)
        }
        .environment(\.colorScheme, .dark)
        .onChange(of: state.expanded) { _, value in
            // Defer NSPanel frame changes until SwiftUI finishes its hosting-view update.
            DispatchQueue.main.async {
                guard state.expanded == value else { return }
                resize(value, reduceMotion)
            }
        }
        .onChange(of: store.summaryEvents.first?.id) { _, _ in state.expanded = true }
        .onExitCommand { state.expanded = false }
    }

    private func widget(_ title: String, icon: String, action: WorkspaceQuickAction) -> some View {
        Button {
            selectedTool = action
            if action == .terminal { terminalStarted = true }
            if action == .codex { codexStarted = true }
        } label: {
            Image(systemName: icon).font(.system(size: 12)).frame(width: 32, height: 32)
        }
        .buttonStyle(.plain).foregroundStyle(selectedTool == action ? palette.primary : .white).help(title).accessibilityLabel(title)
        .accessibilityIdentifier("notch-widget-\(title.lowercased())")
    }

    private var skillsPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Skills").font(.headline)
            TextField("Search skills", text: $skillSearch)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("notch-skills-search")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if store.skillsLibrary.entries.isEmpty {
                        Text("Your saved skills appear here. Add skills from the full workspace.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.skillsLibrary.entries.filter {
                        skillSearch.isEmpty || "\($0.name) \($0.description)".localizedCaseInsensitiveContains(skillSearch)
                    }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { entry in
                        DisclosureGroup(entry.name) {
                            Text(entry.description).font(.callout).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(12)
    }

    private func open(_ action: WorkspaceQuickAction) {
        store.requestQuickAction(action)
        store.openWorkspaceWindow?()
    }
}

struct NotchCapShape: Shape {
    func path(in rect: CGRect) -> Path {
        let shoulder: CGFloat = 12
        let radius = min(24, rect.height / 2)
        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - shoulder, y: rect.minY + shoulder), control: CGPoint(x: rect.maxX - shoulder, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - shoulder, y: rect.maxY - radius))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - shoulder - radius, y: rect.maxY), control: CGPoint(x: rect.maxX - shoulder, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + shoulder + radius, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX + shoulder, y: rect.maxY - radius), control: CGPoint(x: rect.minX + shoulder, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + shoulder, y: rect.minY + shoulder))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.minX + shoulder, y: rect.minY))
            path.closeSubpath()
        }
    }
}

@MainActor
final class NotchSummaryPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    static func host<Content: View>(_ content: Content) -> NSHostingView<Content> {
        let view = NSHostingView(rootView: content)
        // The controller animates fixed panel frames; SwiftUI must not resize its window too.
        view.sizingOptions = []
        return view
    }
}

@MainActor
final class NotchSummaryPanelController: NSObject, NSWindowDelegate {
    private let store: WorkspaceStore
    private let state = NotchSummaryPanelState()
    private var panel: NSPanel?
    private var expanded = false
    private var enabled = false
    private var animateFrameChanges = false
    private var screenObserver: NSObjectProtocol?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    init(store: WorkspaceStore) {
        self.store = store
        super.init()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshScreenMetrics() }
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.collapseIfClickedOutsidePanel() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                guard let self, event.window !== self.panel else { return }
                self.collapseIfClickedOutsidePanel()
            }
            return event
        }
    }

    func stop() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        screenObserver = nil
        globalClickMonitor = nil
        localClickMonitor = nil
        panel?.orderOut(nil)
    }

    func showIfSupported() {
        guard let screen = notchScreen else { return }
        if panel != nil {
            positionPanel(animate: false)
            return
        }
        let panel = NotchSummaryPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.contentView = hostingView(for: screen)
        self.panel = panel
        resize(expanded: false, animated: false)
        panel.orderFrontRegardless()
    }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        expanded = false
        state.expanded = false
        if enabled { showIfSupported() } else { panel?.orderOut(nil) }
    }

    func showExpanded() {
        guard enabled, panel != nil else { return }
        state.expanded = true
    }

    private func resize(expanded: Bool, animated: Bool) {
        self.expanded = expanded
        state.expanded = expanded
        animateFrameChanges = animated
        positionPanel(animate: animated)
    }

    private func positionPanel(animate: Bool) {
        guard enabled, let panel, let screen = notchScreen else { return }
        let target = NotchPanelGeometry.frame(screenFrame: screen.frame, safeAreaTop: screen.safeAreaInsets.top, physicalNotchWidth: Self.notchWidth(on: screen), expanded: expanded)
        if animate && animateFrameChanges {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.36
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
        panel.orderFrontRegardless()
    }

    private func hostingView(for screen: NSScreen) -> NSView {
        let summaryWidth = min(440, max(280, screen.frame.width - 56))
        return NotchSummaryPanel.host(NotchSummaryPanelView(store: store, state: state, safeAreaTop: screen.safeAreaInsets.top, physicalNotchWidth: Self.notchWidth(on: screen), summaryWidth: summaryWidth, resize: { [weak self] expanded, reduceMotion in
            self?.resize(expanded: expanded, animated: !reduceMotion)
        }))
    }

    private func refreshScreenMetrics() {
        guard let panel else { return }
        guard enabled, let screen = notchScreen else {
            panel.orderOut(nil)
            return
        }
        panel.contentView = hostingView(for: screen)
        positionPanel(animate: false)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard expanded else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.expanded else { return }
            self.state.expanded = false
        }
    }

    private var notchScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 24 } ?? NSScreen.main.flatMap { $0.safeAreaInsets.top > 24 ? $0 : nil }
    }

    private static func notchWidth(on screen: NSScreen) -> CGFloat {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let measured = right.minX - left.maxX
            if measured > 50 { return measured }
        }
        return screen.frame.width >= 1700 ? 210 : 180
    }

    private func collapseIfClickedOutsidePanel() {
        guard expanded, let panel, !panel.frame.contains(NSEvent.mouseLocation) else { return }
        state.expanded = false
    }
}

enum NotchPanelGeometry {
    static func frame(screenFrame: NSRect, safeAreaTop: CGFloat, physicalNotchWidth: CGFloat? = nil, expanded: Bool) -> NSRect {
        let availableWidth = max(1, screenFrame.width - 24)
        let notchWidth = physicalNotchWidth ?? (screenFrame.width >= 1700 ? 210 : 180)
        let width = min(expanded ? 480 : notchWidth + 96, availableWidth)
        let height = min(expanded ? safeAreaTop + 250 : max(36, safeAreaTop), max(1, screenFrame.height - 24))
        return NSRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height)
    }
}

@MainActor
final class ShellCommandActivityMonitor {
    private let onCommand: (String, Int32?) -> Void
    private var timer: Timer?
    private var folder: URL?
    private var eventFile: URL?
    private var byteOffset = 0
    private var pending = Data()

    init(onCommand: @escaping (String, Int32?) -> Void) { self.onCommand = onCommand }

    func launchConfiguration(shellPath: String) -> (args: [String], environment: [String]) {
        let root = FileManager.default.temporaryDirectory.appending(path: "dev-command-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let events = root.appending(path: "events")
        FileManager.default.createFile(atPath: events.path, contents: Data(), attributes: [.posixPermissions: 0o600])
        folder = root
        eventFile = events
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.readEvents() }
        }

        let shell = URL(fileURLWithPath: shellPath).lastPathComponent
        var args: [String]
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        environment += ["DEV_ACTIVITY_FILE=\(events.path)"]
        switch shell {
        case "zsh":
            let original = ProcessInfo.processInfo.environment["ZDOTDIR"] ?? NSHomeDirectory()
            environment += ["DEV_ORIGINAL_ZDOTDIR=\(original)", "DEV_SESSION_ZDOTDIR=\(root.path)", "ZDOTDIR=\(root.path)"]
            write("source \"$DEV_ORIGINAL_ZDOTDIR/.zshenv\" 2>/dev/null || true\nexport ZDOTDIR=\"$DEV_SESSION_ZDOTDIR\"\n", to: root.appending(path: ".zshenv"))
            write("export ZDOTDIR=\"$DEV_ORIGINAL_ZDOTDIR\"\nsource \"$DEV_ORIGINAL_ZDOTDIR/.zprofile\" 2>/dev/null || true\nexport ZDOTDIR=\"$DEV_SESSION_ZDOTDIR\"\n", to: root.appending(path: ".zprofile"))
            write("export ZDOTDIR=\"$DEV_ORIGINAL_ZDOTDIR\"\nsource \"$DEV_ORIGINAL_ZDOTDIR/.zshrc\" 2>/dev/null || true\nexport ZDOTDIR=\"$DEV_SESSION_ZDOTDIR\"\ntypeset -g __dev_summary_command=''\nfunction __dev_summary_preexec { __dev_summary_command=\"${1%%[[:space:]]*}\"; if [[ \"$__dev_summary_command\" == *=* ]]; then __dev_summary_command='Command'; fi }\nfunction __dev_summary_precmd { local result=$?; if [[ -n \"$__dev_summary_command\" ]]; then printf '%s\\t%s\\n' \"$(printf %s \"$__dev_summary_command\" | /usr/bin/base64 | /usr/bin/tr -d '\\n')\" \"$result\" >> \"$DEV_ACTIVITY_FILE\"; fi; __dev_summary_command=''; return $result }\npreexec_functions+=(__dev_summary_preexec)\nprecmd_functions+=(__dev_summary_precmd)\n", to: root.appending(path: ".zshrc"))
            write("export ZDOTDIR=\"$DEV_ORIGINAL_ZDOTDIR\"\nsource \"$DEV_ORIGINAL_ZDOTDIR/.zlogin\" 2>/dev/null || true\nexport ZDOTDIR=\"$DEV_SESSION_ZDOTDIR\"\n", to: root.appending(path: ".zlogin"))
            args = ["-l", "-i"]
        case "bash":
            let rc = root.appending(path: "bashrc")
            write("source \"$HOME/.bashrc\" 2>/dev/null || true\n__dev_last_history=\"$(history 1)\"\n__dev_report() { local result=$?; local line; line=\"$(history 1 | /usr/bin/sed -E 's/^ *[0-9]+ +//')\"; if [[ -n \"$line\" && \"$(history 1)\" != \"$__dev_last_history\" ]]; then local label=\"${line%%[[:space:]]*}\"; if [[ \"$label\" == *=* ]]; then label=\"Command\"; fi; printf '%s\\t%s\\n' \"$(printf %s \"$label\" | /usr/bin/base64 | /usr/bin/tr -d '\\n')\" \"$result\" >> \"$DEV_ACTIVITY_FILE\"; __dev_last_history=\"$(history 1)\"; fi; return $result; }\nPROMPT_COMMAND=\"__dev_report${PROMPT_COMMAND:+;$PROMPT_COMMAND}\"\n", to: rc)
            args = ["--login", "--interactive", "--rcfile", rc.path]
        case "fish":
            args = ["-l", "-i", "-C", "function __dev_summary_preexec --on-event fish_preexec; set -g __dev_summary_command $argv[1]; end; function __dev_summary_postexec --on-event fish_postexec; set -l result $status; set -l label (string match -r '^[^[:space:]]+' -- \"$__dev_summary_command\"); if string match -q '*=*' -- \"$label\"; set label Command; end; printf '%s\\t%s\\n' (printf %s \"$label\" | /usr/bin/base64 | /usr/bin/tr -d '\\n') $result >> $DEV_ACTIVITY_FILE; set -g __dev_summary_command ''; end"]
        default:
            // shortcut: command hooks cover zsh, bash, and fish; add an adapter when supporting other shells.
            args = ["-l", "-i"]
        }
        return (args, environment)
    }

    func stop() {
        readEvents()
        timer?.invalidate()
        timer = nil
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
        eventFile = nil
    }

    private func write(_ contents: String, to url: URL) {
        try? Data(contents.utf8).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func readEvents() {
        guard let eventFile, let data = try? Data(contentsOf: eventFile), data.count > byteOffset else { return }
        pending.append(data[byteOffset...])
        byteOffset = data.count
        while let newline = pending.firstIndex(of: 10) {
            let line = Data(pending[..<newline])
            pending.removeSubrange(...newline)
            guard let event = Self.parseEventLine(line) else { continue }
            onCommand(event.command, event.exitCode)
        }
    }

    nonisolated static func parseEventLine(_ line: Data) -> (command: String, exitCode: Int32)? {
        let fields = String(decoding: line, as: UTF8.self).split(separator: "\t", maxSplits: 1)
        guard fields.count == 2, let encoded = Data(base64Encoded: String(fields[0])),
              let command = String(data: encoded, encoding: .utf8), let exitCode = Int32(fields[1]) else { return nil }
        return (command, exitCode)
    }
}
