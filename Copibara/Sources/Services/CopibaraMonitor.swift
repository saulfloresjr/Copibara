import AppKit
import Foundation

@Observable
final class CopibaraMonitor {

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private weak var store: CopibaraStore?

    init(store: CopibaraStore) {
        self.store = store
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else { return }
        // Sync to current clipboard state so we don't re-capture
        // whatever is on the clipboard right now.
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkForChanges() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // If an internal copy triggered this change, skip it
        if store?.suppressNextChange == true {
            store?.suppressNextChange = false
            return
        }

        // Check for image data first (screenshots via ⌘⇧⌃4 go here)
        // Images are NEVER routed to Yapivo — only text transcriptions are.
        if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            // Convert TIFF to PNG if needed for consistent storage
            let pngData: Data
            if pasteboard.data(forType: .png) != nil {
                pngData = imageData
            } else if let nsImage = NSImage(data: imageData),
                      let tiffRep = nsImage.tiffRepresentation,
                      let bitmapRep = NSBitmapImageRep(data: tiffRep),
                      let converted = bitmapRep.representation(using: .png, properties: [:]) {
                pngData = converted
            } else {
                pngData = imageData
            }

            // Avoid duplicate: check if the last item is an image with the same size
            if let latest = store?.items.first,
               latest.type == .image,
               latest.size == pngData.count {
                return
            }

            // Route to the store's default board (never Yapivo, auto-creates Copibara if needed)
            store?.addImageItem(imageData: pngData, boardId: store?.defaultBoardId)
            return
        }

        // Check for string content
        guard let content = pasteboard.string(forType: .string),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        // Avoid duplicating the most recent item
        if let latest = store?.items.first, latest.content == content {
            return
        }

        // Detect Yapivo transcriptions via the custom pasteboard tag.
        // Race-condition guard: Yapivo's Electron first writes plain text via
        // clipboard.writeText(), then 80ms later the FnKeyHelper rewrites the
        // clipboard with BOTH the text AND the "com.yapivo.transcription" tag
        // via the "paste-tagged" command. If our 0.5s poll fires in that 80ms
        // gap we'd see the text WITHOUT the tag → wrong board.
        //
        // Fix: if the tag isn't present on first read, schedule an async
        // re-check after 150ms on a background queue (so we never block the
        // main thread — that would add latency to tilde screenshots, etc.).
        let yapivoPasteboardType = NSPasteboard.PasteboardType("com.yapivo.transcription")
        let isYapivoTranscription = pasteboard.data(forType: yapivoPasteboardType) != nil

        if isYapivoTranscription {
            // Safety: recreate the Yapivo board if it was deleted
            if let store = store, !store.pinboards.contains(where: { $0.id == "yapivo" }) {
                store.pinboards.append(.yapivo)
                store.save()
            }
            store?.addItem(content: content, type: .text, boardId: "yapivo")
        } else {
            // Add to the default board immediately so there's no noticeable lag
            let addedItem = store?.addItem(content: content)

            // Then schedule a deferred re-check: if the Yapivo tag appears
            // within 150ms, re-route the item to the yapivo board.
            let capturedContent = content
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.15) { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self, let store = self.store else { return }
                    let recheckPb = NSPasteboard.general
                    // Only re-route if the pasteboard still has the same text
                    // (if the user copied something else in the interim, bail)
                    guard recheckPb.data(forType: yapivoPasteboardType) != nil else { return }
                    guard let recheckText = recheckPb.string(forType: .string),
                          recheckText == capturedContent else { return }

                    // Re-route: move the item we just added to the yapivo board
                    if let item = addedItem,
                       let idx = store.items.firstIndex(where: { $0.id == item.id }) {
                        store.items[idx].boardId = "yapivo"
                        // Safety: recreate the Yapivo board if it was deleted
                        if !store.pinboards.contains(where: { $0.id == "yapivo" }) {
                            store.pinboards.append(.yapivo)
                        }
                        store.save()
                        print("🎤 CopibaraMonitor: Re-routed item \(item.id) to yapivo (deferred tag detected)")
                    }

                    // Sync changeCount in case paste-tagged bumped it
                    self.lastChangeCount = recheckPb.changeCount
                }
            }
        }
    }
}
