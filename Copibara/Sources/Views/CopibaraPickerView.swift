import SwiftUI
import AppKit

// MARK: - Picker Size Presets

/// Persisted size preset for the clipboard picker.
enum PickerSize: String, CaseIterable {
    case compact  = "compact"
    case regular  = "regular"
    case large    = "large"

    var width: CGFloat {
        switch self {
        case .compact:  return 340
        case .regular:  return 420
        case .large:    return 520
        }
    }

    var height: CGFloat {
        switch self {
        case .compact:  return 400
        case .regular:  return 520
        case .large:    return 640
        }
    }

    var icon: String {
        switch self {
        case .compact:  return "rectangle.compress.vertical"
        case .regular:  return "rectangle"
        case .large:    return "rectangle.expand.vertical"
        }
    }

    var label: String {
        switch self {
        case .compact:  return "S"
        case .regular:  return "M"
        case .large:    return "L"
        }
    }

    /// Cycle to the next size preset.
    var next: PickerSize {
        switch self {
        case .compact:  return .regular
        case .regular:  return .large
        case .large:    return .compact
        }
    }
}

/// Compact copibara picker shown in the floating panel.
/// Supports arrow key navigation, Tab to switch boards, and Enter to paste.
struct CopibaraPickerView: View {
    let store: CopibaraStore
    let onSelect: (CopibaraItem) -> Void
    var onSelectMultiple: (([CopibaraItem]) -> Void)? = nil
    let onDismiss: () -> Void

    @State private var selectedIndex: Int = 0
    /// All selected rows (indices into the current items list) for multi-paste.
    @State private var selectedIndices: Set<Int> = [0]
    /// Fixed end of a Shift range-selection.
    @State private var selectionAnchor: Int = 0
    @State private var searchText: String = ""
    @AppStorage("pickerActiveBoard") private var activeBoard: String = "all"
    @State private var activeTypeFilter: ContentType? = nil
    @State private var keyMonitor: Any?
    @State private var globalKeyMonitor: Any?
    @FocusState private var isSearchFocused: Bool

    /// Persisted picker size preference (survives relaunch).
    @AppStorage("pickerSize") private var pickerSizeRaw: String = PickerSize.compact.rawValue

    private var pickerSize: PickerSize {
        PickerSize(rawValue: pickerSizeRaw) ?? .compact
    }

    /// Yapivo energetic orange
    private let yapivOrange = Color(red: 1.0, green: 0.42, blue: 0.21)

    private var allTabs: [String] {
        ["all"] + store.pinboards.map(\.id)
    }

    private func computeItems() -> [CopibaraItem] {
        var result: [CopibaraItem]
        if activeBoard == "all" {
            result = store.items
        } else {
            result = store.items.filter { $0.boardId == activeBoard }
        }

        // Apply type filter
        if let typeFilter = activeTypeFilter {
            result = result.filter { $0.type == typeFilter }
        }

        if searchText.isEmpty {
            return Array(result.prefix(50))
        }
        let query = searchText.lowercased()
        return result.filter {
            $0.content.lowercased().contains(query) ||
            $0.type.label.lowercased().contains(query)
        }.prefix(50).map { $0 }
    }

    var body: some View {
        let items = computeItems()

        VStack(spacing: 0) {
            // Header
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appTextTertiary)

                TextField("Search clips…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFocused)

                Text("⌘⇧V")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.appTextTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.appBorder.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .background(Color.appSurface)

            // Board Tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    // "All" tab
                    BoardTab(
                        label: "All",
                        icon: "tray.full",
                        isActive: activeBoard == "all"
                    ) {
                        activeBoard = "all"
                        selectedIndex = 0
                    }

                    // Pinboard tabs
                    ForEach(store.pinboards, id: \.id) { board in
                        BoardTab(
                            label: board.name,
                            icon: board.icon,
                            isActive: activeBoard == board.id
                        ) {
                            activeBoard = board.id
                            selectedIndex = 0
                        }
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
            }
            .background(Color.appSurface)

            // Type Filter Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    TypeFilterChip(
                        label: "All",
                        icon: "square.grid.2x2",
                        isActive: activeTypeFilter == nil
                    ) {
                        activeTypeFilter = nil
                        selectedIndex = 0
                    }

                    ForEach(ContentType.allCases, id: \.rawValue) { type in
                        TypeFilterChip(
                            label: type.label.capitalized,
                            emoji: type.emoji,
                            color: type.color,
                            isActive: activeTypeFilter == type
                        ) {
                            activeTypeFilter = type
                            selectedIndex = 0
                        }
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 5)
            }
            .background(Color.appSurface)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.appBorder).frame(height: 0.5)
            }

            // Items List
            if items.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Text("📋")
                        .font(.system(size: 28))
                    Text(activeBoard == "all" ? "No clips found" : "No clips in this board")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.appTextSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Spacing.xl)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                PickerRow(
                                    item: item,
                                    isSelected: selectedIndices.contains(index),
                                    isFocused: index == selectedIndex,
                                    isMulti: selectedIndices.count > 1,
                                    isYapivo: item.boardId == "yapivo",
                                    isForaged: item.capture != nil,
                                    yapivOrange: yapivOrange
                                )
                                .id("\(activeBoard)-\(item.id)")
                                .onTapGesture {
                                    handleRowTap(index: index, item: item)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .id(activeBoard)
                    .onChange(of: selectedIndex) { _, newValue in
                        // Skip scroll animation on filter-reset (selectedIndex goes to 0)
                        let itemId = items.indices.contains(newValue) ? items[newValue].id : 0
                        let scrollId = "\(activeBoard)-\(itemId)"
                        if newValue == 0 {
                            proxy.scrollTo(scrollId, anchor: .top)
                        } else {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo(scrollId, anchor: .center)
                            }
                        }
                    }
                }
            }

            // Footer: hints + size toggle
            HStack(spacing: Spacing.sm) {
                HintLabel(keys: "↑↓", label: "navigate")
                HintLabel(keys: "tab", label: "board")
                HintLabel(keys: "⇧tab", label: "filter")
                HintLabel(keys: "↩", label: selectedIndices.count > 1 ? "paste \(selectedIndices.count)" : "paste")
                HintLabel(keys: "esc", label: "close")

                Spacer()

                // Size preset toggle
                HStack(spacing: 2) {
                    ForEach(PickerSize.allCases, id: \.rawValue) { size in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                pickerSizeRaw = size.rawValue
                            }
                        } label: {
                            Text(size.label)
                                .font(.system(size: 9, weight: pickerSize == size ? .bold : .medium, design: .rounded))
                                .foregroundStyle(pickerSize == size ? Color.appPrimary : Color.appTextTertiary)
                                .frame(width: 20, height: 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(pickerSize == size ? Color.appPrimary.opacity(0.15) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Color.appBorder.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            .background(Color.appSurface)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.appBorder).frame(height: 0.5)
            }
        }
        .frame(width: pickerSize.width, height: pickerSize.height)
        .animation(.easeInOut(duration: 0.2), value: pickerSizeRaw)
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
        .onAppear {
            selectedIndex = 0
            searchText = ""
            // activeBoard is persisted via @AppStorage — don't reset on reopen
            isSearchFocused = true
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: searchText) {
            resetSelectionToTop()
        }
        .onChange(of: activeTypeFilter) {
            resetSelectionToTop()
        }
        .onChange(of: activeBoard) {
            resetSelectionToTop()
        }
        .onChange(of: pickerSizeRaw) { _, newValue in
            // Resize the hosting FloatingPanel and keep it on screen
            if let size = PickerSize(rawValue: newValue),
               let panel = NSApp.windows.compactMap({ $0 as? FloatingPanel }).first(where: { $0.isVisible }) {
                panel.repositionOnScreen(newSize: NSSize(width: size.width, height: size.height))
            }
        }
    }

    // MARK: - Selection

    /// Extend (Shift) or collapse the multi-selection after the cursor moves.
    private func updateSelection(extend: Bool) {
        if extend {
            let lo = min(selectionAnchor, selectedIndex)
            let hi = max(selectionAnchor, selectedIndex)
            selectedIndices = Set(lo...hi)
        } else {
            selectionAnchor = selectedIndex
            selectedIndices = [selectedIndex]
        }
    }

    /// Collapse selection back to the top item (on search/board/filter change).
    private func resetSelectionToTop() {
        selectedIndex = 0
        selectionAnchor = 0
        selectedIndices = [0]
    }

    /// Mouse click on a row: plain = paste one now; Shift or Cmd = toggle that row
    /// individually (non-contiguous, out-of-order multi-select).
    private func handleRowTap(index: Int, item: CopibaraItem) {
        let mods = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.shift) || mods.contains(.command) {
            if selectedIndices.contains(index) {
                selectedIndices.remove(index)
            } else {
                selectedIndices.insert(index)
            }
            selectedIndex = index
            selectionAnchor = index
        } else {
            onSelect(item)
        }
    }

    // MARK: - Key Monitor

    private func installKeyMonitor() {
        // Local monitor: handles all keys when the picker is focused
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case 126: // ↑ arrow
                if selectedIndex > 0 {
                    selectedIndex -= 1
                    updateSelection(extend: event.modifierFlags.contains(.shift))
                }
                return nil
            case 125: // ↓ arrow
                let currentItems = computeItems()
                if selectedIndex < currentItems.count - 1 {
                    selectedIndex += 1
                    updateSelection(extend: event.modifierFlags.contains(.shift))
                }
                return nil
            case 0: // 'A' — ⌘A selects all visible
                if event.modifierFlags.contains(.command) {
                    selectedIndices = Set(computeItems().indices)
                    return nil
                }
                return event
            case 36: // Return — paste the selection (all if multi, else the focused one)
                let currentItems = computeItems()
                guard !currentItems.isEmpty else { return nil }
                let chosen = selectedIndices.sorted().compactMap {
                    currentItems.indices.contains($0) ? currentItems[$0] : nil
                }
                if chosen.count > 1, let pasteMany = onSelectMultiple {
                    pasteMany(chosen)
                } else if currentItems.indices.contains(selectedIndex) {
                    onSelect(currentItems[selectedIndex])
                }
                return nil
            case 53: // Escape
                onDismiss()
                return nil
            case 48: // Tab
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if mods.contains(.shift) {
                    // Shift+Tab: cycle type filter (no animation for snappy feel)
                    let allTypes = ContentType.allCases
                    if let current = activeTypeFilter,
                       let idx = allTypes.firstIndex(of: current) {
                        let nextIdx = idx + 1
                        activeTypeFilter = nextIdx < allTypes.count ? allTypes[nextIdx] : nil
                    } else {
                        activeTypeFilter = allTypes.first
                    }
                    selectedIndex = 0
                } else {
                    // Tab: cycle boards
                    if let idx = allTabs.firstIndex(of: activeBoard) {
                        let nextIdx = (idx + 1) % allTabs.count
                        activeBoard = allTabs[nextIdx]
                        selectedIndex = 0
                    }
                }
                return nil
            default:
                return event // pass through to TextField for typing
            }
        }

        // Global monitor: catches Escape even when picker is NOT focused
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == 53 { // Escape
                onDismiss()
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
    }
}

// MARK: - Board Tab

private struct BoardTab: View {
    let label: String
    let icon: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if icon.count <= 2 {
                    Text(icon)
                        .font(.system(size: 10))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .medium))
                }
                Text(label)
                    .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? Color.appPrimary : Color.appTextSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.appPrimary.opacity(0.12) : (isHovering ? Color.appSurfaceHover : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? Color.appPrimary.opacity(0.25) : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Picker Row

private struct PickerRow: View {
    let item: CopibaraItem
    let isSelected: Bool
    var isFocused: Bool = false
    var isMulti: Bool = false
    var isYapivo: Bool = false
    var isForaged: Bool = false
    var yapivOrange: Color = Color.orange

    /// Same language as the grid card: orange for voice, green for foraged.
    private var accent: Color? {
        if isYapivo { return yapivOrange }
        if isForaged { return .forageAccent }
        return nil
    }

    @State private var isHovering = false
    /// Thumbnail decoded once and cached, so re-rendering on selection change
    /// doesn't re-read the image from disk (which caused multi-select lag).
    @State private var cachedImage: NSImage?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Selection check (multi mode) or type dot — fixed width avoids row reflow
            ZStack {
                if isMulti {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? Color.appPrimary : Color.appTextTertiary)
                } else {
                    Circle()
                        .fill(accent ?? item.type.color)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 14)

            // Content preview
            VStack(alignment: .leading, spacing: 2) {
                if item.type == .image {
                    if let image = cachedImage {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.appBorder, lineWidth: 0.5)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.appSurfaceHover)
                            .frame(width: 64, height: 48)
                    }
                } else {
                    Text(item.preview)
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(Color.appTextPrimary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                HStack(spacing: 4) {
                    if isYapivo {
                        Text("🎙")
                            .font(.system(size: 8))
                    } else if isForaged {
                        Text("🌿")
                            .font(.system(size: 8))
                    }
                    Text("\(item.type.label) · \(item.createdAt.timeAgoDisplay())")
                        .font(.system(size: 10))
                        .foregroundStyle(accent?.opacity(0.7) ?? Color.appTextTertiary)
                }
            }

            Spacer()

            // Type badge
            Text(item.type.emoji)
                .font(.system(size: 12))
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.appPrimary.opacity(0.12) : (isHovering ? Color.appSurfaceHover : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isFocused ? Color.appPrimary.opacity(0.55)
                    : isSelected ? Color.appPrimary.opacity(0.3)
                    : accent?.opacity(0.3) ?? Color.clear,
                    lineWidth: isFocused ? 1.5 : (isSelected ? 1 : (accent != nil ? 1 : 0))
                )
        )
        .shadow(
            color: accent?.opacity(0.15) ?? Color.clear,
            radius: accent != nil ? 4 : 0,
            y: 0
        )
        .padding(.horizontal, 4)
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
        .onAppear {
            guard item.type == .image, cachedImage == nil, let url = imageURL else { return }
            Task { @MainActor in cachedImage = await ImageThumbnail.loadAsync(url, maxPixel: 800) }
        }
        .onDisappear { cachedImage = nil }   // release off-screen rows; shared cache keeps a copy
    }

    private var imageURL: URL? {
        guard let fileName = item.imageFileName else { return nil }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CopibaraManager", isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}

// MARK: - Type Filter Chip

private struct TypeFilterChip: View {
    let label: String
    var icon: String? = nil
    var emoji: String? = nil
    var color: Color = .appPrimary
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .medium))
                } else if let emoji = emoji {
                    Text(emoji)
                        .font(.system(size: 9))
                }
                Text(label)
                    .font(.system(size: 9, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? color : Color.appTextSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? color.opacity(0.12) : (isHovering ? Color.appSurfaceHover : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive ? color.opacity(0.25) : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Footer Hint

private struct HintLabel: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Text(keys)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.appTextTertiary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.appBorder.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 3))

            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Color.appTextTertiary)
        }
    }
}
