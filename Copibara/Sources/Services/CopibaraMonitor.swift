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

            store?.addImageItem(imageData: pngData)
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

        store?.addItem(content: content)
    }
}
