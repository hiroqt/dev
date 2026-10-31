import AppKit
import SwiftUI
import WebKit
import SwiftTerm

private struct WorkspaceFontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var workspaceFontScale: CGFloat {
        get { self[WorkspaceFontScaleKey.self] }
        set { self[WorkspaceFontScaleKey.self] = newValue }
    }
}

private struct WorkspaceFontModifier: ViewModifier {
    @Environment(\.workspaceFontScale) private var scale
    let size: CGFloat
    let weight: Font.Weight?
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

private extension Font.TextStyle {
    var workspaceBaseSize: CGFloat {
        switch self {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline: 13
        case .subheadline: 11
        case .body: 13
        case .callout: 12
        case .footnote, .caption, .caption2: 10
        @unknown default: 13
        }
    }
}

private struct WorkspaceTextStyleFontModifier: ViewModifier {
    @Environment(\.workspaceFontScale) private var scale
    let style: Font.TextStyle
    let weight: Font.Weight?
    let design: Font.Design
    let monospacedDigits: Bool

    func body(content: Content) -> some View {
        let font = Font.system(size: style.workspaceBaseSize * scale, weight: weight, design: design)
        content.font(monospacedDigits ? font.monospacedDigit() : font)
    }
}

extension View {
    func workspaceFont(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design = .default) -> some View {
        modifier(WorkspaceFontModifier(size: size, weight: weight, design: design))
    }

    func workspaceFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design = .default, monospacedDigits: Bool = false) -> some View {
        modifier(WorkspaceTextStyleFontModifier(style: style, weight: weight, design: design, monospacedDigits: monospacedDigits))
    }
}

private struct WorkspaceSurfaceBackground<Style: ShapeStyle>: ViewModifier {
    @AppStorage("contentAreaOpacity") private var opacity = 1.0
    let style: Style

    func body(content: Content) -> some View {
        content.background(style.opacity(opacity))
    }
}

private struct WorkspaceShapedSurfaceBackground<Style: ShapeStyle, Surface: Shape>: ViewModifier {
    @AppStorage("contentAreaOpacity") private var opacity = 1.0
    let style: Style
    let surface: Surface

    func body(content: Content) -> some View {
        content.background(style.opacity(opacity), in: surface)
    }
}

extension View {
    func workspaceSurfaceBackground<Style: ShapeStyle>(_ style: Style) -> some View {
        modifier(WorkspaceSurfaceBackground(style: style))
    }

    func workspaceSurfaceBackground<Style: ShapeStyle, Surface: Shape>(_ style: Style, in surface: Surface) -> some View {
        modifier(WorkspaceShapedSurfaceBackground(style: style, surface: surface))
    }
}

enum WorkspaceBackgroundTheme: String, CaseIterable, Identifiable {
    case pixelMosaic
    case terminalStream
    case auroraGrid

    var id: String { rawValue }
    var title: String {
        switch self {
        case .pixelMosaic: "Pixel Mosaic"
        case .terminalStream: "Terminal Stream"
        case .auroraGrid: "Aurora Wave"
        }
    }
    var subtitle: String {
        switch self {
        case .pixelMosaic: "A full-screen field of large pixels shifts and reforms."
        case .terminalStream: "An animated, palette-colored ASCII field flows across the workspace."
        case .auroraGrid: "A pixelated wave rises beneath flowing glow and palette-colored sparkles."
        }
    }
}

enum WorkspaceThemePalette: String, CaseIterable, Identifiable {
    case aqua
    case violet
    case amber
    case emerald

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var primary: SwiftUI.Color {
        switch self {
        case .aqua: .cyan
        case .violet: .purple
        case .amber: .orange
        case .emerald: .mint
        }
    }
    var secondary: SwiftUI.Color {
        switch self {
        case .aqua: .teal
        case .violet: .indigo
        case .amber: .yellow
        case .emerald: .green
        }
    }
}

struct ThemePresetButton: View {
    let theme: WorkspaceBackgroundTheme
    let selected: Bool
    let palette: WorkspaceThemePalette
    let action: () -> Void
    let choosePalette: (WorkspaceThemePalette) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: action) {
                HStack(spacing: 12) {
                    ThemeSwatch(theme: theme, palette: palette)
                        .frame(width: 74, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(theme.title).workspaceFont(.body, weight: .semibold)
                        Text(theme.subtitle).workspaceFont(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08)))
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("workspace-theme-\(theme.rawValue)")

            HStack(spacing: 9) {
                Text("Color")
                    .workspaceFont(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(palette.title)
                    .workspaceFont(.caption2, weight: .medium)
                    .foregroundStyle(.secondary)
                ForEach(WorkspaceThemePalette.allCases) { option in
                    Button { choosePalette(option) } label: {
                        Circle()
                            .fill(option.primary)
                            .frame(width: 14, height: 14)
                            .padding(3)
                            .overlay(Circle().stroke(palette == option ? Color.primary.opacity(0.8) : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .help("\(option.title) colors for \(theme.title)")
                    .accessibilityLabel("\(option.title) colors for \(theme.title)")
                    .accessibilityAddTraits(palette == option ? .isSelected : [])
                    .accessibilityIdentifier("workspace-theme-\(theme.rawValue)-palette-\(option.rawValue)")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
    }
}

private struct ThemeSwatch: View {
    let theme: WorkspaceBackgroundTheme
    let palette: WorkspaceThemePalette

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [.black, palette.secondary.opacity(0.48)], startPoint: .topLeading, endPoint: .bottomTrailing)
                switch theme {
                case .pixelMosaic:
                    ForEach(0..<42, id: \.self) { index in
                        Rectangle()
                            .fill(index.isMultiple(of: 3) ? palette.primary.opacity(0.9) : palette.secondary.opacity(0.68))
                            .frame(width: index.isMultiple(of: 4) ? 5 : 3, height: index.isMultiple(of: 4) ? 5 : 3)
                            .position(x: CGFloat((index * 13) % max(Int(geometry.size.width), 1)), y: CGFloat((index * 17) % max(Int(geometry.size.height), 1)))
                    }
                case .terminalStream:
                    VStack(alignment: .leading, spacing: 4) {
                        Text(" .,:;+*oO8@8O*+;:. ").foregroundStyle(palette.primary)
                        Text(".:;+*oO8888Oo*+;:. ").foregroundStyle(palette.secondary)
                        Text("  .,:;+*oOOo*+;:,. ").foregroundStyle(palette.primary)
                    }
                    .workspaceFont(size: 6, design: .monospaced)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(6)
                case .auroraGrid:
                    Canvas { context, size in
                        let cell: CGFloat = 4
                        let columns = Int(size.width / cell) + 1
                        let rows = Int(size.height / cell) + 1
                        for column in 0..<columns {
                            let progress = Double(column) / Double(max(columns - 1, 1))
                            let crest = size.height * (0.46 - sin(progress * .pi * 2) * 0.33)
                            for row in 0..<rows {
                                let y = CGFloat(row) * cell
                                guard y + cell >= crest else { continue }
                                let color: SwiftUI.Color = (column + row).isMultiple(of: 3) ? palette.primary : palette.secondary
                                context.fill(Path(CGRect(x: CGFloat(column) * cell, y: y, width: cell, height: cell)), with: .color(color.opacity(0.55)))
                            }
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct WorkspaceThemeBackdrop: View {
    let theme: WorkspaceBackgroundTheme
    let palette: WorkspaceThemePalette
    let reduceMotion: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceFontScale) private var fontScale

    private let asciiGlyphs = Array(" .,:;+*oO8@")

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                guard size.width > 0, size.height > 0 else { return }
                context.opacity = 1
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let rect = CGRect(origin: .zero, size: size)
                if colorScheme != .light {
                    context.fill(Path(rect), with: .color(palette.secondary.opacity(0.045)))
                }
                switch theme {
                case .pixelMosaic:
                    drawPixelMosaic(in: &context, size: size, time: time, palette: palette)
                case .terminalStream:
                    drawTerminalLines(in: &context, size: size, time: time, palette: palette)
                case .auroraGrid:
                    drawAurora(in: &context, size: size, time: time, palette: palette)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawPixelMosaic(in context: inout GraphicsContext, size: CGSize, time: TimeInterval, palette: WorkspaceThemePalette) {
        let cell: CGFloat = 16
        let columns = Int(size.width / cell) + 1
        let rows = Int(size.height / cell) + 1

        for row in 0..<rows {
            let v = Double(row) / Double(max(rows - 1, 1))
            for column in 0..<columns {
                let u = Double(column) / Double(max(columns - 1, 1))
                let driftX = sin(v * 7 + time * 0.13) * 0.55
                let driftY = cos(u * 6 - time * 0.11) * 0.55
                let flow = sin(u * 10 + driftX + time * 0.09)
                    + cos(v * 9 + driftY - time * 0.08)
                    + sin((u * 4 + v * 5) - time * 0.07) * 0.55
                let strength = max(0, (flow + 0.45) / 3.1)
                guard strength > 0.13 else { continue }

                let phase = time * 0.28 + Double(column) * 0.17 + Double(row) * 0.13
                let shimmer = 0.76 + 0.24 * abs(sin(phase))
                let block = cell * (0.48 + CGFloat(strength) * 0.44)
                let color: SwiftUI.Color = (row + column).isMultiple(of: 5) ? palette.primary : palette.secondary
                let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: block, height: block)
                let lightModeBoost = colorScheme == .light ? 2.2 : 1
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color.opacity((0.025 + strength * 0.12) * shimmer * lightModeBoost)))
            }
        }
    }

    private func drawTerminalLines(in context: inout GraphicsContext, size: CGSize, time: TimeInterval, palette: WorkspaceThemePalette) {
        let columns = min(144, max(64, Int(size.width / 10)))
        let rows = min(52, max(24, Int(size.height / 17)))
        let cellHeight = size.height / CGFloat(rows)
        let fontSize = min(12, cellHeight * 0.78)
        let tracking = max(0, size.width / CGFloat(columns) - fontSize * 0.61)

        for row in 0..<rows {
            let y = (Double(row) + 0.5) / Double(rows)
            var glyphRow = ""
            var rowEnergy = 0.0
            for column in 0..<columns {
                let x = ((Double(column) + 0.5) / Double(columns) - 0.5) * Double(size.width / size.height)
                let light = terminalField(x: x, y: y - 0.5, time: time)
                rowEnergy += light
                let level = min(asciiGlyphs.count - 1, max(0, Int(pow(light, 0.76) * Double(asciiGlyphs.count - 1))))
                glyphRow.append(asciiGlyphs[level])
            }

            let average = rowEnergy / Double(columns)
            let color = (row + Int(time * 0.12)).isMultiple(of: 3) ? palette.primary : palette.secondary
            context.draw(
                Text(glyphRow)
                    .font(.system(size: fontSize * fontScale, weight: .regular, design: .monospaced))
                    .tracking(tracking)
                    .foregroundColor(color.opacity(0.12 + min(0.28, average * 0.9))),
                at: CGPoint(x: 14, y: CGFloat(row) * cellHeight + cellHeight * 0.5),
                anchor: .leading
            )
        }
    }

    private func terminalField(x: Double, y: Double, time: TimeInterval) -> Double {
        let breath = (-sin(time * 0.54) + sin(time * 0.36 + 1)) * 0.25 + 0.5
        var u = (x + 0.075) * (1.156 - breath * 0.082)
        var v = (y + 0.587) * (1.156 - breath * 0.082)
        let tilt = -2.119
        let tiltCos = cos(tilt)
        let tiltSin = sin(tilt)
        (u, v) = (u * tiltCos - v * tiltSin, u * tiltSin + v * tiltCos)

        let theta = 2.113
        let foldCos = cos(theta)
        let foldSin = sin(theta)
        let t = time * 0.542 - 66.719
        var glow = 0.0

        for layer in 1...18 {
            let index = Double(layer)
            u += -sin(v * 0.578 + t + index * 0.007) * 0.134
            v += -sin(u * 2.877 - t + index * 0.02) * 0.023
            (u, v) = ((foldCos * u - 0.970 * v) * 0.954, (foldSin * u + foldCos * v) * 0.954)

            let qx = u - 0.420
            let qy = v + 0.034
            let sx = qx * 1.633
            let sy = qy * 0.180
            let radius = hypot(u, v)
            let colorWave = sin(index * 0.198 + t * 1.2 + radius * 1.842) * 0.5 + 0.5
            glow += 0.0023 / (sx * sx + sy * sy + 0.00244) * (0.25 + colorWave * 0.4) * exp(-radius * 0.385)
        }

        let mapped = glow * (2.51 * glow + 0.03) / (glow * (2.43 * glow + 0.59) + 0.14)
        return min(1, max(0, mapped))
    }

    private func drawAurora(in context: inout GraphicsContext, size: CGSize, time: TimeInterval, palette: WorkspaceThemePalette) {
        let cell: CGFloat = 15
        let columns = Int(size.width / cell) + 1
        let rows = Int(size.height / cell) + 1

        for column in 0..<columns {
            let progress = Double(column) / Double(max(columns - 1, 1))
            let crestFraction = auroraCrestFraction(progress: progress, time: time)
            let crestY = size.height * crestFraction
            let x = CGFloat(column) * cell

            for row in 0..<rows {
                let y = CGFloat(row) * cell
                let centerY = y + cell * 0.5
                guard centerY >= crestY else { continue }

                let depth = Double((centerY - crestY) / max(size.height - crestY, 1))
                let crestGlow = max(0, 1 - Double(centerY - crestY) / 72)
                let shimmer = abs(sin(progress * 11 + Double(row) * 0.22 - time * 0.24))
                let opacity = (0.032 + (1 - depth) * 0.045 + crestGlow * 0.085 + shimmer * 0.018) * (colorScheme == .light ? 1.7 : 1)
                let color: SwiftUI.Color = (column + row + Int(time * 0.4)).isMultiple(of: 4) ? palette.primary : palette.secondary
                let rect = CGRect(x: x, y: y, width: min(cell, size.width - x), height: min(cell, size.height - y))
                context.fill(Path(rect), with: .color(color.opacity(opacity)))
            }
        }

        let sparkleCell = CGSize(width: 78, height: 64)
        let sparkleColumns = Int(size.width / sparkleCell.width) + 1
        let sparkleRows = Int(size.height / sparkleCell.height) + 1
        for row in 0..<sparkleRows {
            for column in 0..<sparkleColumns {
                let index = row * sparkleColumns + column
                let seed = Double(index + 1)
                let unitX = (CGFloat(column) + CGFloat(auroraHash(seed * 1.17))) * sparkleCell.width
                let unitY = (CGFloat(row) + CGFloat(auroraHash(seed * 2.31))) * sparkleCell.height
                guard unitX < size.width, unitY < size.height else { continue }

                let progress = Double(unitX / size.width)
                let crestY = size.height * auroraCrestFraction(progress: progress, time: time)
                guard unitY >= crestY + 12 else { continue }

                let fieldX = (progress - 0.5) * Double(size.width / max(size.height, 1))
                let fieldY = Double(unitY / size.height) - 0.5
                let glow = terminalField(x: fieldX, y: fieldY, time: time)
                let presence = min(1, max(0, (glow - 0.08) / 0.36))
                guard presence > 0.025 else { continue }

                let twinkle = pow(max(0, sin(time * (0.8 + auroraHash(seed * 3.73)) + auroraHash(seed * 4.91) * .pi * 2)), 6)
                let opacity = presence * twinkle * 0.62
                guard opacity > 0.015 else { continue }

                let color: SwiftUI.Color = index.isMultiple(of: 2) ? palette.primary : palette.secondary
                var rays = Path()
                let radius: CGFloat = 4 + CGFloat(presence) * 3
                rays.move(to: CGPoint(x: unitX - radius, y: unitY))
                rays.addLine(to: CGPoint(x: unitX + radius, y: unitY))
                rays.move(to: CGPoint(x: unitX, y: unitY - radius))
                rays.addLine(to: CGPoint(x: unitX, y: unitY + radius))
                context.stroke(rays, with: .color(color.opacity(opacity * 0.42)), lineWidth: 1)
                let core = CGRect(x: unitX - 1.5, y: unitY - 1.5, width: 3, height: 3)
                context.fill(Path(ellipseIn: core), with: .color(color.opacity(opacity)))
            }
        }
    }

    private func auroraCrestFraction(progress: Double, time: TimeInterval) -> Double {
        let primarySwell = sin(progress * .pi * 2 - time * 0.11)
        let secondarySwell = sin(progress * .pi + time * 0.065) * 0.085
        let pixelEdge = sin(progress * .pi * 5 + time * 0.14) * 0.035
        return min(0.96, max(0.025, 0.46 - primarySwell * 0.37 + secondarySwell + pixelEdge))
    }

    private func auroraHash(_ value: Double) -> Double {
        let hashed = sin(value * 127.1) * 43758.5453
        return hashed - floor(hashed)
    }
}

struct WorkspaceToolTab: Identifiable, Hashable {
    enum Kind: String { case browser, terminal }
    let id = UUID()
    let kind: Kind
    let workingDirectory: URL?
    let initialCommand: String?
    var title: String { kind == .browser ? "Browser" : initialCommand == "codex" ? "Codex" : "Terminal" }
    var icon: String { kind == .browser ? "globe" : "terminal" }
    var isCodex: Bool { initialCommand == "codex" }
}

private struct ToolRecentProject: Identifiable {
    let id: String
    let title: String
    let path: String
    let icon: String
    let destination: Destination
}

struct WorkspaceToolsPanel: View {
    @Bindable var store: WorkspaceStore
    @Binding var tabs: [WorkspaceToolTab]
    @Binding var selectedTabID: UUID?
    @Binding var showingLauncher: Bool
    @Binding var isFullScreen: Bool
    let currentProjectFolder: URL?
    let openProject: (Destination) -> Void
    let closePanel: () -> Void

    private var recentProjects: [ToolRecentProject] {
        store.recentProjects.prefix(3).compactMap { reference in
            switch reference {
            case let .local(id):
                guard let project = store.localProjects.first(where: { $0.id == id }), let url = project.url else { return nil }
                return ToolRecentProject(id: reference.id, title: project.name, path: url.path, icon: "folder.fill", destination: .localProject(id, .overview))
            case let .github(id):
                guard let repo = store.repository(id: id), let path = store.clonedRepositoryPaths[id] else { return nil }
                return ToolRecentProject(id: reference.id, title: repo.name, path: path, icon: "shippingbox.fill", destination: .project(id, .overview))
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            ZStack {
                ForEach(tabs) { tab in
                    Group {
                        switch tab.kind {
                        case .browser: EmbeddedBrowserTab()
                        case .terminal: EmbeddedTerminalTab(store: store, directory: tab.workingDirectory, initialCommand: tab.initialCommand)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(!showingLauncher && selectedTabID == tab.id ? 1 : 0)
                    .allowsHitTesting(!showingLauncher && selectedTabID == tab.id)
                    .accessibilityHidden(showingLauncher || selectedTabID != tab.id)
                }
                if showingLauncher || tabs.isEmpty { launcher }
            }
        }
        .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1) }
    }

    private var tabBar: some View {
        HStack(spacing: 5) {
            if tabs.isEmpty {
                Text("Tools").workspaceFont(.headline)
                Spacer()
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(tabs) { tab in
                            HStack(spacing: 2) {
                                Button {
                                    selectedTabID = tab.id
                                    showingLauncher = false
                                } label: {
                                    HStack(spacing: 6) {
                                        if tab.isCodex {
                                            Image("CodexMark").resizable().scaledToFit().frame(width: 16, height: 16)
                                        } else {
                                            Image(systemName: tab.icon)
                                        }
                                        Text(tab.title).lineLimit(1)
                                    }
                                    .padding(.leading, 8).padding(.vertical, 7)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("tool-tab-select-\(tab.id)")
                                Button { closeTab(tab) } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                                        .frame(width: 22, height: 24)
                                }
                                .buttonStyle(.plain)
                                .help("Close \(tab.title) tab")
                                .accessibilityLabel("Close \(tab.title) tab")
                            }
                            .background(selectedTabID == tab.id && !showingLauncher ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            Button {
                showingLauncher = true
            } label: {
                Image(systemName: "plus").frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("New tool tab")
            .accessibilityLabel("New tool tab")
            Button { isFullScreen.toggle() } label: {
                Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(isFullScreen ? "Exit full-screen preview" : "Full-screen preview")
            .accessibilityLabel(isFullScreen ? "Exit full-screen preview" : "Full-screen preview")
            .accessibilityIdentifier("tool-preview-fullscreen")
            Button(action: closePanel) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Close tools panel")
            .accessibilityLabel("Close tools panel")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var launcher: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Tools").workspaceFont(.title3, weight: .bold)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    toolCard("Browser", detail: "Open a website", icon: "globe") { addTab(.browser) }
                    toolCard("Terminal", detail: "Run a shell", icon: "terminal") { addTab(.terminal) }
                    toolCard("Codex", detail: "Start Codex in this project", icon: "terminal", iconAsset: "CodexMark") { addTab(.terminal, initialCommand: "codex") }
                }
                HStack {
                    Text("Recent projects").workspaceFont(.headline)
                    Spacer()
                    Text("Last opened").workspaceFont(.caption).foregroundStyle(.tertiary)
                }
                if recentProjects.isEmpty {
                    Text("Open or clone a project to see it here.")
                        .workspaceFont(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    VStack(spacing: 4) {
                        ForEach(recentProjects) { project in
                            Button { openProject(project.destination) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: project.icon).foregroundStyle(project.icon == "folder.fill" ? .teal : Color.accentColor).frame(width: 22)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(project.title).workspaceFont(.body, weight: .medium).lineLimit(1)
                                        Text(project.path).workspaceFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: "arrow.up.left").workspaceFont(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("tool-recent-project-\(project.id)")
                        }
                    }
                    .padding(5).background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                }
                Label("Terminal commands run with your macOS account permissions. The project path sets the starting folder only.", systemImage: "info.circle")
                    .workspaceFont(.caption).foregroundStyle(.secondary)
            }
            .padding(18)
        }
    }

    private func toolCard(_ title: String, detail: String, icon: String, iconAsset: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                if let iconAsset {
                    Image(iconAsset).resizable().scaledToFit().frame(width: 24, height: 24)
                } else {
                    Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundStyle(Color.accentColor)
                }
                Text(title).workspaceFont(.body, weight: .semibold)
                Text(detail).workspaceFont(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .padding(12).background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tool-launch-\(title.lowercased())")
    }

    private func addTab(_ kind: WorkspaceToolTab.Kind, initialCommand: String? = nil) {
        let tab = WorkspaceToolTab(kind: kind, workingDirectory: kind == .terminal ? currentProjectFolder ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true) : nil, initialCommand: initialCommand)
        tabs.append(tab)
        selectedTabID = tab.id
        showingLauncher = false
    }

    private func closeTab(_ tab: WorkspaceToolTab) {
        tabs.removeAll { $0.id == tab.id }
        if tabs.isEmpty {
            closePanel()
        } else if selectedTabID == tab.id {
            selectedTabID = tabs.last?.id
            showingLauncher = false
        }
    }
}

private struct EmbeddedBrowserTab: View {
    @State private var webView = WKWebView()
    @State private var address = ""
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button { webView.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!canGoBack).help("Back")
                Button { webView.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!canGoForward).help("Forward")
                Button { webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Reload")
                TextField("Search or enter a URL", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(navigate)
                    .accessibilityIdentifier("embedded-browser-address")
            }
            .buttonStyle(.plain)
            .padding(9)
            .overlay(alignment: .bottom) { Divider() }
            if isLoading { ProgressView().controlSize(.small).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10) }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .workspaceFont(.caption).foregroundStyle(.secondary).padding(8)
            }
            BrowserWebView(webView: webView, address: $address, canGoBack: $canGoBack, canGoForward: $canGoForward, isLoading: $isLoading, error: $error)
        }
    }

    private func navigate() {
        let entered = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entered.isEmpty else { return }
        let candidate = entered.contains("://") ? entered : "https://\(entered)"
        if let url = safeBrowserURL(candidate) {
            error = nil
            webView.load(URLRequest(url: url))
            return
        }
        var search = URLComponents(string: "https://duckduckgo.com/")!
        search.queryItems = [URLQueryItem(name: "q", value: entered)]
        if let url = search.url {
            error = nil
            webView.load(URLRequest(url: url))
        }
    }
}

private struct BrowserWebView: NSViewRepresentable {
    let webView: WKWebView
    @Binding var address: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var error: String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        return webView
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        view.navigationDelegate = context.coordinator
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: BrowserWebView
        init(_ parent: BrowserWebView) { self.parent = parent }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, safeBrowserURL(url.absoluteString) != nil else {
                decisionHandler(.cancel)
                return
            }
            if action.targetFrame == nil {
                webView.load(action.request)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.error = nil
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { update(webView, loading: false) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(webView, error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(webView, error) }
        private func update(_ webView: WKWebView, loading: Bool) {
            parent.address = webView.url?.absoluteString ?? parent.address
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
            parent.isLoading = loading
        }
        private func fail(_ webView: WKWebView, _ error: Error) {
            update(webView, loading: false)
            parent.error = error.localizedDescription
        }
    }
}

private func safeBrowserURL(_ value: String) -> URL? {
    guard let url = URL(string: value),
          let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
          ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
          let host = parts.host, !host.isEmpty,
          parts.user == nil, parts.password == nil else { return nil }
    return url
}

struct EmbeddedTerminalTab: View {
    @Bindable var store: WorkspaceStore
    let directory: URL?
    let initialCommand: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(directory?.path ?? NSHomeDirectory()).workspaceFont(.caption, design: .monospaced).lineLimit(1).truncationMode(.middle)
                Spacer()
            }
            .padding(9).overlay(alignment: .bottom) { Divider() }
            LocalTerminalRepresentable(store: store, directory: directory, initialCommand: initialCommand)
        }
    }
}

private struct LocalTerminalRepresentable: NSViewRepresentable {
    @Bindable var store: WorkspaceStore
    let directory: URL?
    let initialCommand: String?
    @AppStorage("contentAreaOpacity") private var surfaceOpacity = 1.0
    @AppStorage("workspaceFontSize") private var workspaceFontSize = "medium"

    private var terminalFontSize: CGFloat {
        switch workspaceFontSize {
        case "small": 11
        case "large": 16
        case "xl": 20
        default: 14
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(store: store, directory: directory, initialCommand: initialCommand) }
    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.font = .monospacedSystemFont(ofSize: terminalFontSize, weight: .regular)
        terminal.backgroundOpacity = surfaceOpacity
        terminal.processDelegate = context.coordinator
        context.coordinator.start(in: terminal)
        return terminal
    }
    func updateNSView(_ terminal: LocalProcessTerminalView, context: Context) {
        terminal.font = .monospacedSystemFont(ofSize: terminalFontSize, weight: .regular)
        terminal.backgroundOpacity = surfaceOpacity
    }
    static func dismantleNSView(_ terminal: LocalProcessTerminalView, coordinator: Coordinator) {
        terminal.terminate()
    }

    @MainActor
    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        private let store: WorkspaceStore
        private let directory: URL?
        private let initialCommand: String?
        private var hasDirectoryAccess = false
        private var activityMonitor: ShellCommandActivityMonitor?
        private var reportedInitialCommand = false
        init(store: WorkspaceStore, directory: URL?, initialCommand: String?) {
            self.store = store
            self.directory = directory
            self.initialCommand = initialCommand
        }
        func start(in terminal: LocalProcessTerminalView) {
            if let directory { hasDirectoryAccess = directory.startAccessingSecurityScopedResource() }
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let monitor = ShellCommandActivityMonitor { [weak self] command, exitCode in
                guard let self else { return }
                self.store.recordCommandActivity(command: command, exitCode: exitCode)
                if command == self.initialCommand { self.reportedInitialCommand = true }
            }
            activityMonitor = monitor
            var configuration = monitor.launchConfiguration(shellPath: shell)
            if let initialCommand { configuration.args += ["-c", initialCommand] }
            terminal.startProcess(executable: shell, args: configuration.args, environment: configuration.environment, currentDirectory: directory?.path ?? NSHomeDirectory())
        }
        nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
            Task { @MainActor in
                if let initialCommand = self.initialCommand, !self.reportedInitialCommand {
                    self.store.recordCommandActivity(command: initialCommand, exitCode: exitCode)
                }
                self.activityMonitor?.stop()
                self.releaseDirectoryAccess()
            }
        }
        nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func releaseDirectoryAccess() {
            guard hasDirectoryAccess, let directory else { return }
            directory.stopAccessingSecurityScopedResource()
            hasDirectoryAccess = false
        }
    }
}
