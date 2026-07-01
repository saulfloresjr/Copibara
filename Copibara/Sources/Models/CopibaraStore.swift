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
    var activeBoard: String = "all"
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

    /// The default board ID for new non-voice items.
    /// RULE: Never returns "yapivo" — only voice transcriptions go there.
    /// If no non-Yapivo board exists, auto-creates the default Copibara board.
    var defaultBoardId: String {
        // If the user is viewing a specific non-Yapivo board, use it
        if activeBoard != "all" && activeBoard != "yapivo",
           pinboards.contains(where: { $0.id == activeBoard }) {
            return activeBoard
        }
        // Fall back to first non-Yapivo board
        if let board = pinboards.first(where: { $0.id != "yapivo" }) {
            return board.id
        }
        // No non-Yapivo board exists — auto-create the default Copibara board
        pinboards.insert(.clipboard, at: 0)
        save()
        return Pinboard.clipboard.id
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
        save()
        return item
    }

    /// Add an image item (e.g. from a screenshot).
    @discardableResult
    func addImageItem(imageData: Data, boardId: String? = nil) -> CopibaraItem {
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
            imageFileName: fileName
        )
        nextId += 1
        items.insert(item, at: 0)
        save()
        return item
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

    /// AI-upscale a small image for sharing (waifu2x 2× + Lanczos to target) and put
    /// the result on the clipboard. Does not add a new clip.
    func aiUpscale(id: Int) {
        guard let item = items.first(where: { $0.id == id }),
              let fileName = item.imageFileName else {
            toast = "That clip isn't an image"
            return
        }
        let url = imagesDir.appendingPathComponent(fileName)
        toast = "Enhancing…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let data = try? Data(contentsOf: url),
                  let upscaled = AIUpscaler.upscaledPNG(from: data) else {
                DispatchQueue.main.async { self?.toast = "Couldn't enhance that image" }
                return
            }
            DispatchQueue.main.async {
                self?.suppressNextChange = true
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setData(upscaled, forType: .png)
                let dims = NSBitmapImageRep(data: upscaled).map { " (\($0.pixelsWide)×\($0.pixelsHigh))" } ?? ""
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
        // Safety: never clear when viewing "all" boards
        guard activeBoard != "all" else { return }
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

    /// Nuclear option: clear every item across all boards.
    func clearAllBoards() {
        for item in items {
            if let fileName = item.imageFileName {
                let fileURL = imagesDir.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        items.removeAll()
        save()
    }

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
            activeBoard = "all"
        }
        save()
    }

    // MARK: - Filtering

    func filteredItems(search: String) -> [CopibaraItem] {
        // "all" shows items from every board; otherwise filter by active board
        var result = activeBoard == "all"
            ? items
            : items.filter { $0.boardId == activeBoard }
        if !search.isEmpty {
            let query = search.lowercased()
            result = result.filter {
                $0.content.lowercased().contains(query) ||
                $0.type.label.lowercased().contains(query)
            }
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
