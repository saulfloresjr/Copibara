import Foundation
import SwiftUI

// MARK: - Persistence Model

private struct StoreData: Codable {
    var items: [CopibaraItem]
    var pinboards: [Pinboard]
    var nextId: Int
}

// MARK: - Clipboard Store

@Observable
final class CopibaraStore {

    var items: [CopibaraItem] = []
    var pinboards: [Pinboard] = [.clipboard, .yapivo]
    var activeBoard: String = BoardFilter.all
    var nextId: Int = 1

    /// When true, the monitor will skip the next clipboard change.
    /// Used to prevent internal copy operations from creating duplicates.
    var suppressNextChange = false

    /// Transient status message shown as a toast in the main window.
    var toast: String?

    private let fileURL: URL
    let imagesDir: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("CopibaraManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.fileURL = appDir.appendingPathComponent("data.json")

        // Create images directory for screenshot storage
        self.imagesDir = appDir.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        load()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            seedDemoData()
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let store = try? decoder.decode(StoreData.self, from: data) else {
            seedDemoData()
            return
        }

        self.items = store.items
        self.pinboards = store.pinboards
        self.nextId = store.nextId

        // Migration: ensure default Yapivo board exists for existing users
        if !pinboards.contains(where: { $0.id == "yapivo" }) {
            pinboards.append(.yapivo)
        }
        // Migration: Forage mode's Collected board
        if !pinboards.contains(where: { $0.id == "collected" }) {
            pinboards.append(.collected)
        }

        // Enforce the history cap on the loaded set — this is where an existing
        // oversized history (tens of thousands of clips) gets pruned down once, which
        // shrinks both the in-memory items and the next startup decode. Pinned/foraged
        // clips are untouched. Persist immediately so the trim survives a crash.
        let before = items.count
        trimIfNeeded()
        if items.count != before { save() }

        // Save on app quit to make sure nothing is lost
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.save()
        }
    }

    func save() {
        let store = StoreData(items: items, pinboards: pinboards, nextId: nextId)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(store) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Items

    /// Boards that only their own capture path may write to.
    private static let reservedBoardIds: Set<String> = ["yapivo", "collected"]

    /// The default board ID for new non-voice items.
    /// RULE: Never returns "yapivo" (voice only) or "collected" (Forage mode only).
    /// If no ordinary board exists, auto-creates the default Copibara board.
    var defaultBoardId: String {
        // If the user is viewing a specific ordinary board, use it
        if !BoardFilter.isVirtual(activeBoard), !Self.reservedBoardIds.contains(activeBoard),
           pinboards.contains(where: { $0.id == activeBoard }) {
            return activeBoard
        }
        // Fall back to first ordinary board
        if let board = pinboards.first(where: { !Self.reservedBoardIds.contains($0.id) }) {
            return board.id
        }
        // No non-Yapivo board exists — auto-create the default Copibara board
        pinboards.insert(.clipboard, at: 0)
        save()
        return Pinboard.clipboard.id
    }

    // MARK: - History cap

    /// Keep at most this many UNPINNED items. Foraged/pinned and favourited clips are
    /// never trimmed — the whole point of keeping one is that it outlives routine
    /// churn. Bounds both memory and the startup JSON decode as history grows.
    /// Configurable via defaults.
    var maxUnpinnedHistory: Int {
        let v = UserDefaults.standard.integer(forKey: "maxUnpinnedHistory")
        return v > 0 ? v : 10_000
    }

    /// Total bytes across all stored clips (image PNG bytes + text bytes). Cheap — each
    /// item already carries its own `size`, so this is an in-memory sum, no disk scan.
    var totalStoredBytes: Int {
        items.reduce(0) { $0 + $1.size }
    }
    /// Trim only once the overflow reaches this, then drop the batch — so the O(n)
    /// pass runs about once every `trimSlack` adds instead of on every single copy.
    private let trimSlack = 200

    /// Drop the oldest unpinned items past the cap (items are newest-first), deleting
    /// their image files too. Does NOT save — the caller persists.
    private func trimIfNeeded() {
        let cap = maxUnpinnedHistory
        guard items.count > cap + trimSlack else { return }   // fast path: usually skipped
        var keptUnpinned = 0
        var removed: [CopibaraItem] = []
        items.removeAll { item in
            if item.isKept { return false }                   // never trim pinned/foraged/favourited
            if keptUnpinned < cap { keptUnpinned += 1; return false }
            removed.append(item)
            return true
        }
        for item in removed {
            if let fileName = item.imageFileName {
                try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(fileName))
            }
        }
        if !removed.isEmpty {
            print("[Copibara] history cap: trimmed \(removed.count) old unpinned item(s)")
        }
    }

    @discardableResult
    func addItem(content: String, type: ContentType? = nil, boardId: String? = nil) -> CopibaraItem {
        let detectedType = type ?? detectContentType(content)
        let item = CopibaraItem(
            id: nextId,
            content: content,
            type: detectedType,
            preview: generatePreview(content, type: detectedType),
            createdAt: Date(),
            boardId: boardId ?? defaultBoardId,
            size: content.utf8.count
        )
        nextId += 1
        items.insert(item, at: 0)
        trimIfNeeded()
        save()
        return item
    }

    /// Add an image item (e.g. from a screenshot).
    @discardableResult
    func addImageItem(
        imageData: Data,
        boardId: String? = nil,
        capture: CaptureContext? = nil,
        pinned: Bool = false
    ) -> CopibaraItem {
        // Save image to disk
        let fileName = "screenshot_\(nextId)_\(Int(Date().timeIntervalSince1970)).png"
        let fileURL = imagesDir.appendingPathComponent(fileName)
        try? imageData.write(to: fileURL, options: .atomic)

        let sizeKB = imageData.count / 1024
        let content = "[Screenshot – \(sizeKB) KB]"

        let item = CopibaraItem(
            id: nextId,
            content: content,
            type: .image,
            preview: "📸 Screenshot (\(sizeKB) KB)",
            createdAt: Date(),
            boardId: boardId ?? defaultBoardId,
            size: imageData.count,
            imageFileName: fileName,
            capture: capture,
            pinned: pinned ? true : nil
        )
        nextId += 1
        items.insert(item, at: 0)
        trimIfNeeded()
        save()
        return item
    }

    // MARK: - Forage

    /// File a capture made while Forage mode was armed: it lands on the Collected
    /// board, is pinned against bulk clears, and gets an async OCR pass that both
    /// makes it searchable and backfills the source if no URL was available.
    func addForagedImage(imageData: Data, context: CaptureContext?) {
        // Safety: recreate the Collected board if it was deleted.
        if !pinboards.contains(where: { $0.id == "collected" }) {
            pinboards.append(.collected)
        }

        let item = addImageItem(
            imageData: imageData,
            boardId: Pinboard.collected.id,
            capture: context ?? CaptureContext(),
            pinned: true
        )

        // Immediate feedback from whatever the URL already told us.
        let headline = context?.displaySource.map { "Collected from \($0)" } ?? "Collected"
        Task { @MainActor in
            ForageHUD.shared.show(icon: "🌿", title: headline, subtitle: "saved to Collected")
        }

        let id = item.id
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let text = TextRecognizer.recognize(in: imageData) else { return }
            DispatchQueue.main.async {
                self?.attachRecognizedText(text, to: id)
            }
        }
    }

    /// File a text clip collected while Forage mode was armed. No OCR needed — and
    /// unlike a screenshot there's no crosshair stealing focus, so the source can be
    /// read at copy time rather than latched in advance.
    func addForagedText(content: String, context: CaptureContext?) {
        if !pinboards.contains(where: { $0.id == "collected" }) {
            pinboards.append(.collected)
        }

        // If the URL didn't identify a source, the copied text itself might.
        var resolved = context ?? CaptureContext()
        if resolved.handle == nil {
            let found = SourceParser.handle(inText: content)
            resolved.handle = found.handle
            if let kind = found.kind { resolved.kind = kind }
        }

        let type = detectContentType(content)
        let item = CopibaraItem(
            id: nextId,
            content: content,
            type: type,
            preview: generatePreview(content, type: type),
            createdAt: Date(),
            boardId: Pinboard.collected.id,
            size: content.utf8.count,
            capture: resolved,
            pinned: true
        )
        nextId += 1
        items.insert(item, at: 0)
        save()

        let headline = resolved.displaySource.map { "Collected from \($0)" } ?? "Collected"
        Task { @MainActor in
            ForageHUD.shared.show(icon: "🌿", title: headline, subtitle: "text saved to Collected")
        }
    }

    /// Fold OCR results into a foraged item — searchable text, plus a source and
    /// engagement count if we can spot them in the pixels.
    private func attachRecognizedText(_ text: String, to id: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var context = items[index].capture ?? CaptureContext()
        context.ocrText = text

        // Fallback source: "r/homestead" is usually right there in the screenshot,
        // even when the URL was unavailable.
        if context.handle == nil {
            let found = SourceParser.handle(inText: text)
            if let handle = found.handle {
                context.handle = handle
                if context.kind == nil || context.kind == .app || context.kind == .web {
                    context.kind = found.kind ?? context.kind
                }
                Task { @MainActor in
                    ForageHUD.shared.show(icon: "🌿", title: "Collected from \(handle)", subtitle: "saved to Collected")
                }
            }
        }
        if context.socialProof == nil {
            context.socialProof = SourceParser.socialProof(inText: text)
        }

        items[index].capture = context
        save()
    }

    /// Export the image to a user-selected location
    func exportImage(for id: Int) {
        guard let item = items.first(where: { $0.id == id }),
              item.type == .image,
              let fileName = item.imageFileName else { return }

        let fileURL = imagesDir.appendingPathComponent(fileName)
        
        // Show save panel
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Save Image"

        // Ensure this happens on the main thread
        DispatchQueue.main.async {
            if panel.runModal() == .OK, let targetURL = panel.url {
                do {
                    if FileManager.default.fileExists(atPath: targetURL.path) {
                        try FileManager.default.removeItem(at: targetURL)
                    }
                    try FileManager.default.copyItem(at: fileURL, to: targetURL)
                } catch {
                    print("Failed to save image: \(error)")
                }
            }
        }
    }

    /// Remove the background from an image item via Vision, putting the transparent-
    /// background cutout on the clipboard (also captured as a new clip by the monitor).
    func removeBackground(id: Int) {
        guard let item = items.first(where: { $0.id == id }),
              let fileName = item.imageFileName else {
            toast = "That clip isn't an image"
            return
        }
        let url = imagesDir.appendingPathComponent(fileName)
        toast = "Removing background…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let data = try? Data(contentsOf: url),
                  let cutout = SubjectExtractor.cutout(from: data) else {
                DispatchQueue.main.async { self?.toast = "Couldn't find a subject to lift" }
                return
            }
            DispatchQueue.main.async {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setData(cutout, forType: .png)
                let dims = NSBitmapImageRep(data: cutout).map { " (\($0.pixelsWide)×\($0.pixelsHigh))" } ?? ""
                self?.toast = "Background removed\(dims) — paste anywhere, also saved as a clip"
            }
        }
    }

    /// AI-upscale an image and put the result on the clipboard. Does not add a new
    /// clip — you asked for a bigger version of this image, not a second copy of it.
    func aiUpscale(id: Int, mode: UpscaleMode = .fit(AIUpscaler.defaultTarget)) {
        guard let item = items.first(where: { $0.id == id }),
              let fileName = item.imageFileName else {
            toast = "That clip isn't an image"
            return
        }
        let url = imagesDir.appendingPathComponent(fileName)
        toast = "Enhancing…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let data = try? Data(contentsOf: url) else {
                DispatchQueue.main.async { self?.toast = "Couldn't read that image" }
                return
            }
            let upscaled = AIUpscaler.upscaledPNG(from: data, mode: mode) { status in
                DispatchQueue.main.async { self?.toast = status }
            }
            guard let upscaled else {
                DispatchQueue.main.async { self?.toast = "Couldn't enhance that image" }
                return
            }
            DispatchQueue.main.async {
                self?.suppressNextChange = true
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setData(upscaled, forType: .png)
                let dims = NSBitmapImageRep(data: upscaled)
                    .map { " (\($0.pixelsWide)×\($0.pixelsHigh))" } ?? ""
                self?.toast = "Enhanced\(dims) — paste anywhere (⌘V)"
            }
        }
    }

    func deleteItem(id: Int) {
        // If it's an image item, also delete the image file
        if let item = items.first(where: { $0.id == id }), let fileName = item.imageFileName {
            let fileURL = imagesDir.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
        items.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
        // Safety: never clear from a virtual board — "All" and "Favorites" are views
        // over the real boards, so there's no single board here to empty.
        guard !BoardFilter.isVirtual(activeBoard) else { return }
        // Delete image files for items being cleared
        let toRemove = items.filter { $0.boardId == activeBoard }
        for item in toRemove {
            if let fileName = item.imageFileName {
                let fileURL = imagesDir.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        items.removeAll { $0.boardId == activeBoard }
        save()
    }

    /// Clear a specific board by its ID (used from the "All" board menu).
    func clearBoard(id: String) {
        let toRemove = items.filter { $0.boardId == id }
        for item in toRemove {
            if let fileName = item.imageFileName {
                let fileURL = imagesDir.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        items.removeAll { $0.boardId == id }
        save()
    }

    /// Nuclear option: clear every item across all boards — except the ones you kept
    /// on purpose: foraged finds and favourites.
    ///
    /// Those survive this deliberately. The whole point of collecting or starring is
    /// that the good stuff outlives routine clipboard churn; a cleanup you run monthly
    /// shouldn't take out the content bank you've been building, or the links you
    /// paste every day. To remove them, unfavourite them, clear the Collected board
    /// directly, or delete them individually.
    func clearAllBoards() {
        for item in items where !item.isKept {
            if let fileName = item.imageFileName {
                let fileURL = imagesDir.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        items.removeAll { !$0.isKept }
        save()
    }

    /// How many pinned items "Clear Everything" would leave behind.
    var pinnedCount: Int { items.filter(\.isPinned).count }

    /// How many clips survive "Clear Everything" — pinned/foraged plus favourites.
    var keptCount: Int { items.filter(\.isKept).count }

    /// Copy item content to the system clipboard. Handles both text and image items.
    func copyToClipboard(id: Int) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        
        // Suppress the monitor so it doesn't re-capture this as a duplicate
        suppressNextChange = true
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let fileName = item.imageFileName {
            // Image item — write image data to pasteboard
            let fileURL = imagesDir.appendingPathComponent(fileName)
            if let imageData = try? Data(contentsOf: fileURL) {
                pasteboard.setData(imageData, forType: .png)
            }
        } else {
            pasteboard.setString(item.content, forType: .string)
        }
    }

    /// Bulk-copy multiple items to the system clipboard.
    /// Text items are joined with double newlines; if only images, the first is placed on the pasteboard.
    func copyItemsToClipboard(ids: Set<Int>) {
        let selected = items.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let textItems = selected.filter { $0.imageFileName == nil }
        let imageItems = selected.filter { $0.imageFileName != nil }

        if !textItems.isEmpty {
            let combined = textItems.map(\.content).joined(separator: "\n\n")
            pasteboard.setString(combined, forType: .string)
        } else if let firstImage = imageItems.first, let fileName = firstImage.imageFileName {
            let fileURL = imagesDir.appendingPathComponent(fileName)
            if let imageData = try? Data(contentsOf: fileURL) {
                pasteboard.setData(imageData, forType: .png)
            }
        }
    }

    /// Bulk-delete multiple items (including their image files).
    func deleteItems(ids: Set<Int>) {
        for item in items where ids.contains(item.id) {
            if let fileName = item.imageFileName {
                let fileURL = imagesDir.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        items.removeAll { ids.contains($0.id) }
        save()
    }

    // MARK: - Favorites

    /// How many clips are starred — shown on the Favorites tab so the shortlist's
    /// size is visible without opening it.
    var favoriteCount: Int { items.reduce(0) { $0 + ($1.isFavorite ? 1 : 0) } }

    func isFavorite(id: Int) -> Bool {
        items.first(where: { $0.id == id })?.isFavorite ?? false
    }

    /// Flip a clip's star. Returns the new state so callers can phrase their toast.
    ///
    /// Unstarring writes `nil` rather than `false` so the key leaves data.json
    /// entirely — favourites then cost nothing for the vast majority of clips that
    /// never get one.
    @discardableResult
    func toggleFavorite(id: Int) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        let now = !items[index].isFavorite
        items[index].favorite = now ? true : nil
        save()
        return now
    }

    /// Star or unstar a whole selection in one write — one `save()` for the batch,
    /// not one per clip.
    func setFavorite(_ favorite: Bool, ids: Set<Int>) {
        guard !ids.isEmpty else { return }
        for index in items.indices where ids.contains(items[index].id) {
            items[index].favorite = favorite ? true : nil
        }
        save()
    }

    /// Star the most recent clip — the hands-free "favorite that" path, so a link you
    /// just copied joins the shortlist without touching the mouse.
    /// Returns the item it starred, or nil if there was nothing to star.
    @discardableResult
    func favoriteLatest() -> CopibaraItem? {
        guard let index = items.indices.first else {
            toast = "Nothing to favorite yet"
            return nil
        }
        items[index].favorite = true
        save()
        let item = items[index]
        toast = "⭐️ Favorited \(item.preview.prefix(40))"
        return item
    }

    // MARK: - Pinboards

    func addPinboard(name: String, icon: String = "📌") {
        let id = name.lowercased().replacingOccurrences(of: " ", with: "_") + "_\(Int(Date().timeIntervalSince1970))"
        let board = Pinboard(id: id, name: name, icon: icon, isDefault: false)
        pinboards.append(board)
        save()
    }

    func deletePinboard(id: String) {
        guard pinboards.contains(where: { $0.id == id }) else { return }
        // Delete all items in this board (including image files)
        let boardItems = items.filter { $0.boardId == id }
        for item in boardItems {
            if let fileName = item.imageFileName {
                let fileURL = imagesDir.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        items.removeAll { $0.boardId == id }
        pinboards.removeAll { $0.id == id }
        if activeBoard == id {
            activeBoard = BoardFilter.all
        }
        save()
    }

    // MARK: - Filtering

    func filteredItems(search: String) -> [CopibaraItem] {
        // "all" shows every board, "favorites" the starred shortlist across boards;
        // anything else filters to that one board.
        var result: [CopibaraItem]
        switch activeBoard {
        case BoardFilter.all:       result = items
        case BoardFilter.favorites: result = items.filter(\.isFavorite)
        default:                    result = items.filter { $0.boardId == activeBoard }
        }
        if !search.isEmpty {
            let query = search.lowercased()
            result = result.filter { $0.matches(query) }
        }
        return result
    }

    func item(for id: Int) -> CopibaraItem? {
        items.first { $0.id == id }
    }

    // MARK: - Seed Data

    private func seedDemoData() {
        let demoItems: [(String, ContentType)] = [
            ("https://developer.apple.com/swift/", .link),
            ("Meeting notes: Q4 product roadmap review with design team. Key takeaways — focus on performance, new onboarding flow, and dark mode polish.", .text),
            ("""
            func fibonacci(_ n: Int) -> Int {
                guard n > 1 else { return n }
                return fibonacci(n - 1) + fibonacci(n - 2)
            }
            """, .code),
            ("https://github.com/apple/swift", .link),
            ("Remember to buy: milk, eggs, bread, and coffee beans from the farmers market on Saturday morning.", .text),
            ("""
            struct ContentView: View {
                @State private var count = 0
                var body: some View {
                    Button("Tap me: \\(count)") {
                        count += 1
                    }
                }
            }
            """, .code),
            ("The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs.", .text),
            ("https://www.figma.com/design/clipboard-manager", .link),
            ("""
            SELECT users.name, orders.total
            FROM users
            JOIN orders ON users.id = orders.user_id
            WHERE orders.created_at > '2024-01-01'
            ORDER BY orders.total DESC;
            """, .code),
            ("Email draft: Hi team, I wanted to follow up on our conversation about the new feature launch timeline. Can we schedule a sync for Thursday?", .text),
        ]

        for (content, type) in demoItems {
            let item = CopibaraItem(
                id: nextId,
                content: content,
                type: type,
                preview: generatePreview(content, type: type),
                createdAt: Date().addingTimeInterval(-Double(nextId * 300)),
                boardId: "clipboard",
                size: content.utf8.count
            )
            nextId += 1
            items.append(item)
        }
        save()

        // Register for quit notification
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.save()
        }
    }
}
