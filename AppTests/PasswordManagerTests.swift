import XCTest
@testable import dev

private actor VaultStub: PasswordVaultAccess {
    var saved = [PasswordEntry(service: "Google", username: "me@example.com", password: "secret")]
    var failUnlock = false
    var failSave = false
    func configure(unlock: Bool = false, save: Bool = false) { failUnlock = unlock; failSave = save }
    func unlock() throws -> [PasswordEntry] {
        if failUnlock { throw PasswordVaultError.keychain(-128) }
        return saved
    }
    func save(_ entries: [PasswordEntry]) throws {
        if failSave { throw PasswordVaultError.keychain(-1) }
        saved = entries
    }
    func lock() {}
}

private actor DelayedVault: PasswordVaultAccess {
    private let gate = AsyncStream<[PasswordEntry]>.makeStream()
    private var waiting = false
    func unlock() async -> [PasswordEntry] {
        waiting = true
        var iterator = gate.stream.makeAsyncIterator()
        return await iterator.next() ?? []
    }
    func started() -> Bool { waiting }
    func finish() {
        gate.continuation.yield([PasswordEntry(service: "Google", username: "me", password: "secret")])
        gate.continuation.finish()
    }
    func save(_ entries: [PasswordEntry]) {}
    func lock() {}
}

@MainActor
final class PasswordManagerTests: XCTestCase {
    func testLockRejectsLateUnlockResult() async {
        let vault = DelayedVault()
        let store = PasswordManagerStore(vault: vault)
        let unlocking = Task { await store.unlock() }
        for _ in 0..<1000 {
            if await vault.started() { break }
            await Task.yield()
        }
        let started = await vault.started()
        XCTAssertTrue(started)
        store.lock()
        await vault.finish()
        await unlocking.value
        XCTAssertFalse(store.unlocked)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testCancelledUnlockDoesNotExposePasswords() async {
        let vault = VaultStub()
        await vault.configure(unlock: true)
        let store = PasswordManagerStore(vault: vault)
        await store.unlock()
        XCTAssertFalse(store.unlocked)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNotNil(store.error)
    }

    func testFailedSavePreservesEntriesAndLockClearsMemory() async {
        let vault = VaultStub()
        let store = PasswordManagerStore(vault: vault)
        await store.unlock()
        let original = store.entries
        await vault.configure(save: true)
        let success = await store.save(PasswordEntry(service: "Apple", username: "another", password: "new"))
        XCTAssertFalse(success)
        XCTAssertEqual(store.entries, original)
        store.lock()
        XCTAssertFalse(store.unlocked)
        XCTAssertTrue(store.entries.isEmpty)
        let lockedSave = await store.save(original[0])
        XCTAssertFalse(lockedSave)
    }

    func testDeletionPersistsOnlySelectedLogin() async {
        let vault = VaultStub()
        let store = PasswordManagerStore(vault: vault)
        await store.unlock()
        let removed = store.entries[0]
        let added = PasswordEntry(service: "Apple", username: "keep", password: "keep-password")
        _ = await store.save(added)
        let deleted = await store.delete(removed.id)
        XCTAssertTrue(deleted)
        XCTAssertEqual(store.entries, [added])
        let persisted = try? await vault.unlock()
        XCTAssertEqual(persisted, [added])
        let staleEdit = await store.save(removed)
        XCTAssertFalse(staleEdit)
        XCTAssertEqual(store.entries, [added])
        store.lock()
        let lockedDelete = await store.delete(added.id)
        XCTAssertFalse(lockedDelete)
    }

    func testFailedDeletionPreservesSavedLogin() async {
        let vault = VaultStub()
        let store = PasswordManagerStore(vault: vault)
        await store.unlock()
        let original = store.entries
        await vault.configure(save: true)
        let deleted = await store.delete(original[0].id)
        XCTAssertFalse(deleted)
        XCTAssertEqual(store.entries, original)
        let persisted = try? await vault.unlock()
        XCTAssertEqual(persisted, original)
        XCTAssertNotNil(store.error)
    }

    func testMultipleAccountsAndEditingKeepIdentity() async {
        let store = PasswordManagerStore(vault: VaultStub())
        await store.unlock()
        let added = await store.save(PasswordEntry(service: "Google", username: "second", password: "second-password"))
        XCTAssertTrue(added)
        XCTAssertEqual(store.entries.count, 2)
        var entry = store.entries[0]
        entry.password = "updated"
        let edited = await store.save(entry)
        XCTAssertTrue(edited)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries[0].password, "updated")
        let invalid = await store.save(PasswordEntry(service: "  ", username: "name", password: "secret"))
        XCTAssertFalse(invalid)
    }
}
