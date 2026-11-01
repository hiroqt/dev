import SwiftUI
import AppKit

@MainActor @Observable
final class PasswordManagerStore {
    static let shared = PasswordManagerStore()
    private let vault: any PasswordVaultAccess
    init(vault: any PasswordVaultAccess = PasswordVault()) { self.vault = vault }
    private var generation = UUID()
    private var deletedIDs: Set<UUID> = []
    private var pendingLock: Task<Void, Never>?
    var entries: [PasswordEntry] = []
    var unlocked = false
    var busy = false
    var error: String?
    private var clipboardChange: Int?

    func copyPassword(_ password: String) {
        guard unlocked else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        pasteboard.setString(password, forType: .string)
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let change = pasteboard.changeCount
        clipboardChange = change
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            if pasteboard.changeCount == change { pasteboard.clearContents() }
        }
    }

    func unlock() async {
        guard !busy else { return }
        let request = generation
        busy = true
        error = nil
        await pendingLock?.value
        guard request == generation else { return }
        do {
            let saved = try await vault.unlock()
            guard request == generation else { return }
            entries = saved
            unlocked = true
        } catch {
            guard request == generation else { return }
            self.error = error is DecodingError ? "The vault could not be read. Saved data has been preserved." : error.localizedDescription
        }
        if request == generation { busy = false }
    }

    func save(_ entry: PasswordEntry) async -> Bool {
        guard unlocked, !busy else { return false }
        guard !deletedIDs.contains(entry.id) else {
            error = "This login was deleted. Close the editor and add a new login if needed."
            return false
        }
        guard entry.isValid else { error = PasswordVaultError.invalidEntry.localizedDescription; return false }
        var updated = entries
        if let index = updated.firstIndex(where: { $0.id == entry.id }) { updated[index] = entry }
        else { updated.append(entry) }
        return await persist(updated)
    }

    func delete(_ id: UUID) async -> Bool {
        guard unlocked, !busy, entries.contains(where: { $0.id == id }) else { return false }
        let deleted = await persist(entries.filter { $0.id != id })
        if deleted { deletedIDs.insert(id) }
        return deleted
    }

    private func persist(_ updated: [PasswordEntry]) async -> Bool {
        let request = generation
        busy = true
        do {
            try await vault.save(updated)
            guard request == generation else { return false }
            entries = updated
            busy = false
            error = nil
            return true
        } catch {
            guard request == generation else { return false }
            self.error = error.localizedDescription
            busy = false
            return false
        }
    }

    func lock() {
        if let clipboardChange, NSPasteboard.general.changeCount == clipboardChange {
            NSPasteboard.general.clearContents()
        }
        clipboardChange = nil
        generation = UUID()
        deletedIDs = []
        entries = []
        unlocked = false
        busy = false
        error = nil
        let previousLock = pendingLock
        let vault = vault
        pendingLock = Task {
            await previousLock?.value
            await vault.lock()
        }
    }
}

struct PasswordManagerView: View {
    @State private var store = PasswordManagerStore.shared
    @State private var search = ""
    @State private var editing: PasswordEntry?
    @State private var pendingDeletion: PasswordEntry?
    @State private var revealed: Set<UUID> = []
    @Environment(\.scenePhase) private var scenePhase
    private let services = ["Google", "Facebook", "Apple", "Microsoft", "Amazon", "Instagram", "GitHub", "Netflix", "Other"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Password Manager", systemImage: "lock.shield")
                    .workspaceFont(size: 24, weight: .semibold)
                Spacer()
                if store.unlocked {
                    Button("Add Login", systemImage: "plus") {
                        editing = PasswordEntry(service: "Google", username: "", password: "")
                    }.disabled(store.busy)
                    Button("Lock", systemImage: "lock") { lock() }
                }
            }
            if let error = store.error {
                Text(error).foregroundStyle(.red).accessibilityIdentifier("vault-error")
            }
            if store.unlocked {
                TextField("Search service or username", text: $search)
                    .textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if store.entries.isEmpty {
                            Text("No saved logins. Add Google, Facebook, Apple or any other service.")
                                .foregroundStyle(.secondary).padding()
                        }
                        ForEach(store.entries.filter {
                            search.isEmpty || $0.service.localizedCaseInsensitiveContains(search) || $0.username.localizedCaseInsensitiveContains(search)
                        }) { entry in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(entry.service).workspaceFont(size: 17, weight: .semibold)
                                Text(entry.username).textSelection(.enabled)
                                Text(revealed.contains(entry.id) ? entry.password : "••••••••••••")
                                    .font(.system(.body, design: .monospaced))
                                    .privacySensitive()
                                    .accessibilityLabel(revealed.contains(entry.id) ? entry.password : "Hidden password")
                                HStack(spacing: 8) {
                                    Spacer()
                                    Button {
                                        if !revealed.insert(entry.id).inserted { revealed.remove(entry.id) }
                                    } label: {
                                        Image(systemName: revealed.contains(entry.id) ? "eye.slash" : "eye")
                                            .frame(width: 28, height: 28)
                                    }
                                    .accessibilityLabel(revealed.contains(entry.id) ? "Hide password" : "Reveal password")
                                    .help(revealed.contains(entry.id) ? "Hide password" : "Reveal password")
                                    Button { store.copyPassword(entry.password) } label: {
                                        Image(systemName: "doc.on.doc").frame(width: 28, height: 28)
                                    }
                                    .accessibilityLabel("Copy password")
                                    .help("Copy password")
                                    Button { editing = entry } label: {
                                        Image(systemName: "pencil").frame(width: 28, height: 28)
                                    }
                                    .disabled(store.busy)
                                    .accessibilityLabel("Edit login")
                                    .help("Edit login")
                                    Button(role: .destructive) { pendingDeletion = entry } label: {
                                        Image(systemName: "trash").frame(width: 28, height: 28)
                                            .foregroundStyle(.red)
                                    }
                                    .disabled(store.busy)
                                    .accessibilityLabel("Delete login")
                                    .help("Delete login")
                                }
                                .buttonStyle(.borderless)

                            }
                            .padding().background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            } else {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield").font(.system(size: 48))
                    Text("Your passwords stay on this Mac.").workspaceFont(size: 18, weight: .semibold)
                    Text("Unlock using your Mac password in the macOS security prompt.")
                        .foregroundStyle(.secondary)
                    Button(store.busy ? "Unlocking…" : "Unlock Password Manager") {
                        Task { await store.unlock() }
                    }
                    .disabled(store.busy).accessibilityIdentifier("vault-unlock")
                }.frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(24)
        .sheet(item: $editing) { entry in
            PasswordEntryEditor(entry: entry, services: services, store: store) { editing = nil }
                .dismissOnOutsideClick()
        }
        .alert("Delete login?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        ), presenting: pendingDeletion) { entry in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    if await store.delete(entry.id) { revealed.remove(entry.id) }
                }
            }
        } message: { entry in
            Text("Delete the saved login for \(entry.username) on \(entry.service)? This cannot be undone.")
        }
        .onDisappear { lock() }
        .onChange(of: store.unlocked) { _, unlocked in
            if !unlocked { editing = nil; pendingDeletion = nil; revealed = []; search = "" }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { lock() } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in lock() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)) { _ in lock() }
        .onReceive(DistributedNotificationCenter.default().publisher(for: Notification.Name("com.apple.screenIsLocked"))) { _ in lock() }
    }

    private func lock() {
        pendingDeletion = nil
        editing = nil
        revealed = []
        search = ""
        store.lock()
    }
}

private struct PasswordEntryEditor: View {
    @State var entry: PasswordEntry
    let services: [String]
    let store: PasswordManagerStore
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Login").workspaceFont(size: 20, weight: .semibold)
            Picker("Service preset", selection: $entry.service) {
                ForEach(Array(Set(services + [entry.service])).sorted(), id: \.self) { Text($0).tag($0) }
            }
            TextField("Service", text: $entry.service)
            TextField("Email or username", text: $entry.username)
            SecureField("Password", text: $entry.password)
            if let error = store.error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { Task { if await store.save(entry) { close() } } }
                    .disabled(!entry.isValid || store.busy).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 420)
    }
}
