import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SkillsLibraryView: View {
    let store: WorkspaceStore
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var selectedID: UUID?
    @State private var sourceURL = ""
    @State private var isPickingFolder = false
    @State private var deleteEntry: SkillEntry?
    @State private var showsCompactDetail = false

    private var library: SkillsLibraryStore { store.skillsLibrary }
    private var categories: [String] { ["All"] + Array(Set(library.entries.map(\.category))).sorted() }
    private var filtered: [SkillEntry] {
        library.entries.filter { entry in
            (selectedCategory == "All" || entry.category == selectedCategory)
                && (searchText.isEmpty || [entry.name, entry.description, entry.category, entry.source, entry.tags.joined(separator: " ")]
                    .contains(where: { $0.localizedCaseInsensitiveContains(searchText) }))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private var selected: SkillEntry? { filtered.first(where: { $0.id == selectedID }) ?? filtered.first }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if library.entries.isEmpty {
                    catalog
                        .frame(maxWidth: 900)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if geometry.size.width < 760 {
                    if showsCompactDetail, let selected {
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                showsCompactDetail = false
                            } label: {
                                Label("Back to Skills", systemImage: "chevron.left")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("skills-back-to-catalog")

                            SkillDetailView(entry: selected, store: store, remove: { deleteEntry = selected })
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                        }
                    } else {
                        catalog.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    HStack(spacing: 14) {
                        catalog
                            .frame(minWidth: 340, idealWidth: 390, maxWidth: 470)
                        if let selected {
                            SkillDetailView(entry: selected, store: store, remove: { deleteEntry = selected })
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ContentUnavailableView("No matching skills", systemImage: "magnifyingglass", description: Text("Change the search or category filter."))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            Task { await store.addSkillFolder(url) }
        }
        .confirmationDialog("Remove this skill and its offline copy?", isPresented: Binding(
            get: { deleteEntry != nil },
            set: { if !$0 { deleteEntry = nil } }
        ), titleVisibility: .visible) {
            Button("Remove Skill", role: .destructive) {
                guard let deleteEntry else { return }
                Task { await library.remove(deleteEntry) }
                selectedID = nil
                self.deleteEntry = nil
            }
        }
    }

    private var catalog: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Skills").workspaceFont(size: 21, weight: .semibold)
                Spacer()
                Button {
                    Task { await store.scanAllSkillRepositories() }
                } label: {
                    Label(library.isScanning ? "Scanning" : "Scan Clones", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(library.isScanning)
                .accessibilityIdentifier("skills-scan-clones")
            }
            HStack(spacing: 10) {
                TextField("Search name, purpose, or tags", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .workspaceFont(.body)
                    .padding(.vertical, 5)
                    .accessibilityIdentifier("skills-search")
                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .controlSize(.large)
                .frame(width: 160)
            }
            HStack {
                Button {
                    isPickingFolder = true
                } label: {
                    Label("Add Folder…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("skills-add-folder")
                Spacer()
                Text("\(filtered.count) skills")
                    .workspaceFont(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                TextField("GitHub URL or search term", text: $sourceURL)
                    .textFieldStyle(.roundedBorder)
                    .workspaceFont(.body)
                    .padding(.vertical, 5)
                    .onSubmit { submitSource() }
                    .accessibilityIdentifier("skills-github-query")
                Button {
                    submitSource()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(library.isSearching || sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Search GitHub or add a GitHub URL")
                .accessibilityIdentifier("skills-github-search")
            }
            if !library.candidates.isEmpty {
                Text("GitHub candidates")
                    .workspaceFont(size: 13, weight: .semibold)
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(library.candidates) { candidate in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(candidate.name).workspaceFont(.subheadline, weight: .medium)
                                    Text(candidate.source).workspaceFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    if !candidate.description.isEmpty {
                                        Text(candidate.description).workspaceFont(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }
                                Spacer()
                                Button("Add") { Task { await store.addGitHubSkill(candidate) } }
                                    .buttonStyle(.bordered)
                            }
                            .padding(9)
                            .workspaceSurfaceBackground(.quaternary, in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
                .frame(maxHeight: 170)
            }
            if let error = library.error {
                Text(error).workspaceFont(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            List(filtered, selection: Binding(
                get: { selected?.id },
                set: {
                    selectedID = $0
                    if $0 != nil { showsCompactDetail = true }
                }
            )) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.name).workspaceFont(.headline)
                        Spacer()
                        if entry.state == .unavailable {
                            Label("Offline copy", systemImage: "arrow.down.circle")
                                .workspaceFont(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Text(entry.description.isEmpty ? "No description" : entry.description)
                        .workspaceFont(.caption).foregroundStyle(.secondary).lineLimit(2)
                    HStack {
                        Text(entry.category)
                        if !entry.tags.isEmpty { Text("· \(entry.tags.joined(separator: ", "))").lineLimit(1) }
                    }
                    .workspaceFont(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                .tag(entry.id)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .simultaneousGesture(TapGesture().onEnded { showsCompactDetail = true })
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "Your library is empty" : "No matching skills",
                        systemImage: searchText.isEmpty ? "sparkles.rectangle.stack" : "magnifyingglass",
                        description: Text(searchText.isEmpty
                            ? "Add a folder, scan a clone, or search GitHub to save skills for offline use."
                            : "Try another name, purpose, tag, or category.")
                    )
                    .accessibilityIdentifier("skills-empty-state")
                }
            }
            .accessibilityIdentifier("skills-catalog")
        }
        .padding(20)
        .frame(maxHeight: .infinity)
        .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    private func submitSource() {
        let value = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if value.lowercased().hasPrefix("https://github.com/") {
                await library.addGitHubURL(value, accessToken: store.githubAccessToken)
            } else {
                await store.searchGitHubSkills(value)
            }
        }
    }
}

private struct SkillDetailView: View {
    let entry: SkillEntry
    let store: WorkspaceStore
    let remove: () -> Void
    @State private var selectedFile: String?
    @State private var category: String

    init(entry: SkillEntry, store: WorkspaceStore, remove: @escaping () -> Void) {
        self.entry = entry
        self.store = store
        self.remove = remove
        _category = State(initialValue: entry.category)
        _selectedFile = State(initialValue: entry.files.first(where: { $0.lowercased().hasSuffix("skill.md") }) ?? entry.files.first)
    }

    private var preview: LocalProjectTextFile? {
        guard let selectedFile,
              selectedFile.split(separator: "/").allSatisfy({ $0 != "." && $0 != ".." && !$0.hasPrefix(".") }) else { return nil }
        let url = entry.folderURL.appending(path: selectedFile)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= 2_000_000,
              let contents = try? String(contentsOf: url, encoding: .utf8), !contents.unicodeScalars.contains(where: { $0.value == 0 }) else { return nil }
        let ext = url.pathExtension.lowercased()
        return LocalProjectTextFile(contents: contents, isMarkdown: ["md", "markdown"].contains(ext), language: ext.isEmpty ? "Text" : ext.uppercased())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.name).workspaceFont(size: 22, weight: .semibold)
                    Text(entry.description.isEmpty ? "No description" : entry.description)
                        .workspaceFont(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Refresh Source") { Task { await store.refreshSkill(entry) } }
                    Button("Remove Skill…", role: .destructive, action: remove)
                } label: { Image(systemName: "ellipsis.circle").font(.title2) }
                    .menuStyle(.borderlessButton)
                    .accessibilityLabel("Skill actions")
            }
            HStack {
                Text("Category").workspaceFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                TextField("Category", text: $category)
                    .textFieldStyle(.roundedBorder)
                    .workspaceFont(.body)
                    .padding(.vertical, 4)
                    .frame(maxWidth: 220)
                    .onSubmit { Task { await store.skillsLibrary.setCategory(category, for: entry) } }
                    .accessibilityIdentifier("skill-category")
                Button("Save") { Task { await store.skillsLibrary.setCategory(category, for: entry) } }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || category == entry.category)
                if entry.state == .unavailable {
                    Label("Source unavailable; offline copy kept", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                        .workspaceFont(.caption).foregroundStyle(.orange)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                ForEach(entry.tags, id: \.self) { tag in
                    Text(tag).workspaceFont(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
            }
            HStack {
                Text("Source: \(entry.source)").workspaceFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let url = entry.sourceURL.flatMap(URL.init(string:)), url.host == "github.com" {
                    Link("Open", destination: url).workspaceFont(.caption)
                }
                Spacer()
                Text("Stored: \(entry.storedFolder)").workspaceFont(.caption2).foregroundStyle(.tertiary).lineLimit(1).textSelection(.enabled)
            }
            if let command = entry.installCommand {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Install command").workspaceFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                        Text(command).workspaceFont(.caption, design: .monospaced).textSelection(.enabled)
                        if let source = entry.installCommandSource { Text(source).workspaceFont(.caption2).foregroundStyle(.tertiary) }
                    }
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("skill-copy-command")
                }
                .padding(12)
                .workspaceSurfaceBackground(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
            Divider()
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Files").workspaceFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                    List(entry.files, id: \.self, selection: $selectedFile) { file in
                        Text(file).workspaceFont(.caption, design: .monospaced).lineLimit(1).tag(file)
                    }
                    .listStyle(.inset)
                    .frame(width: 250)
                }
                if let preview {
                    ScrollView {
                        if preview.isMarkdown {
                            MarkdownMessageView(markdown: preview.contents, id: "skill-\(entry.id)")
                        } else {
                            Text(preview.contents).workspaceFont(.body, design: .monospaced)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                    .workspaceSurfaceBackground(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("skill-offline-preview")
                } else {
                    ContentUnavailableView(
                        selectedFile == nil ? "No files" : "Preview unavailable",
                        systemImage: "doc.text",
                        description: Text(selectedFile.map { "\($0) is binary, missing, or larger than 2 MB." } ?? "This skill has no stored files.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: entry.category) { _, value in category = value }
    }
}
