import XCTest
@testable import Copibara

/// Large clips live on disk past `CopibaraItem.inlineTextLimit`; these check that no
/// text is ever lost doing that, and that search still finds what it should.
final class LargeTextTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("copibara-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Capture

    func testLargeClipIsStoredOnDiskAndPastesInFull() {
        let store = CopibaraStore(directory: dir)
        let big = String(repeating: "{ \"role\": \"AXImage\", \"é\": 1 }\n", count: 40_000)  // ~1.3 MB

        let item = store.addItem(content: big)

        XCTAssertTrue(item.isTextTruncated)
        XCTAssertLessThanOrEqual(item.content.utf8.count, CopibaraItem.inlineTextLimit)
        XCTAssertEqual(store.fullText(for: item), big)
        XCTAssertEqual(item.size, big.utf8.count)
        XCTAssertTrue(store.isSameAsLatest(big))
        XCTAssertFalse(store.isSameAsLatest(big + "x"))
    }

    func testSmallClipStaysInline() {
        let store = CopibaraStore(directory: dir)
        let item = store.addItem(content: "hello world")
        XCTAssertFalse(item.isTextTruncated)
        XCTAssertEqual(store.fullText(for: item), "hello world")
        XCTAssertTrue(store.isSameAsLatest("hello world"))
    }

    func testDeletingRemovesTheTextFile() throws {
        let store = CopibaraStore(directory: dir)
        let item = store.addItem(content: String(repeating: "x", count: 200_000))
        let file = store.textsDir.appendingPathComponent(try XCTUnwrap(item.contentFileName))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        store.deleteItem(id: item.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testReloadKeepsFullText() {
        let big = String(repeating: "line of a long clip\n", count: 10_000)
        let first = CopibaraStore(directory: dir)
        let id = first.addItem(content: big).id
        first.saveNow()

        let reloaded = CopibaraStore(directory: dir)
        let item = try? XCTUnwrap(reloaded.item(for: id))
        XCTAssertEqual(item.map { reloaded.fullText(for: $0) }, big)
    }

    // MARK: - Helpers

    func testUTF8PrefixNeverSplitsACharacter() {
        let s = String(repeating: "é", count: 10)   // 2 bytes each
        XCTAssertEqual(s.utf8Prefix(5), "éé")         // 5 bytes would split the third é
        XCTAssertEqual(s.utf8Prefix(100), s)
    }

    func testSearchMatchesLikeFoundation() {
        let haystacks = ["Hello World", "COPIBARA rocks", "nothing here", "École de Paris", ""]
        for q in ["hello", "WORLD", "copibara", "zzz", "école", "o r"] {
            let query = SearchQuery(q)
            for h in haystacks {
                let expected = !h.isEmpty && h.range(of: query.text, options: .caseInsensitive) != nil
                let item = CopibaraItem(id: 1, content: h, type: .text, preview: h,
                                        createdAt: Date(), boardId: "clipboard", size: h.utf8.count)
                // `matches` also checks the type label ("TEXT"), so only assert real hits.
                if expected { XCTAssertTrue(item.matches(query), "\(q) in \(h)") }
                if !expected && !"text".contains(query.text) {
                    XCTAssertFalse(item.matches(query), "\(q) in \(h)")
                }
            }
        }
    }

    // MARK: - Real history (only on the developer's machine)

    /// Migrates a COPY of the real data.json in a temp folder — the live store is
    /// never touched — and checks every clip's text survives byte-for-byte.
    func testMigrationOfRealHistoryLosesNothing() throws {
        let live = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CopibaraManager/data.json")
        guard FileManager.default.fileExists(atPath: live.path) else {
            throw XCTSkip("no local Copibara history")
        }
        try FileManager.default.copyItem(at: live, to: dir.appendingPathComponent("data.json"))

        struct Raw: Decodable { struct Item: Decodable { let id: Int; let content: String }; let items: [Item] }
        let original = try JSONDecoder().decode(Raw.self, from: Data(contentsOf: live)).items
        let originalText = Dictionary(original.map { ($0.id, $0.content) }, uniquingKeysWith: { a, _ in a })

        var t = Date()
        let migrated = CopibaraStore(directory: dir)        // load + one-time migration
        print("[perf] first launch (load + migration): \(ms(since: t))")

        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("data.pre-1.8-backup.json").path))
        let spilledCount = migrated.items.filter(\.isTextTruncated).count
        print("[migration] \(spilledCount) clip(s) moved to disk")

        func assertNoTextLost(_ store: CopibaraStore, _ label: String) {
            var checked = 0
            for item in store.items {
                guard let text = originalText[item.id] else { continue }   // trimmed by the cap
                XCTAssertEqual(store.fullText(for: item), text, "\(label): clip \(item.id) changed")
                XCTAssertLessThanOrEqual(item.content.utf8.count, CopibaraItem.inlineTextLimit)
                checked += 1
            }
            print("[\(label)] \(checked) clips verified byte-identical")
        }
        assertNoTextLost(migrated, "after migration")

        let size = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("data.json").path)[.size] as? Int ?? 0
        print("[size] data.json now \(size / 1_000_000) MB")

        t = Date()
        let reloaded = CopibaraStore(directory: dir)
        print("[perf] later launch (load): \(ms(since: t))")
        assertNoTextLost(reloaded, "after reload")

        t = Date()
        reloaded.saveNow()
        print("[perf] one save: \(ms(since: t))")

        for q in ["zzqxw", "copibara", "the"] {
            t = Date()
            let hits = reloaded.filteredItems(search: q).count
            print("[perf] search \"\(q)\": \(ms(since: t)), \(hits) hits")
        }
    }

    private func ms(since t: Date) -> String {
        String(format: "%.0f ms", Date().timeIntervalSince(t) * 1000)
    }
}
