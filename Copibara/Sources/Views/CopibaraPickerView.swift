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

    /// Board to open on, overriding whatever the user last had selected. Set when the
    /// picker is summoned *at* something — "favorite links" by voice, say — so that
    /// summon doesn't quietly rewrite the tab a plain ⌘⇧V returns to.
    var initialBoard: String? = nil
    /// Type filter to open with, same deal.
    var initialTypeFilter: ContentType? = nil

    @State private var selectedIndex: Int = 0
    /// All selected rows (indices into the current items list) for multi-paste.
    @State private var selectedIndices: Set<Int> = [0]
    /// Fixed end of a Shift range-selection.
    @State private var selectionAnchor: Int = 0
    @State private var searchText: String = ""
    /// The board the user last picked *by hand*. A summon-with-a-target (see
    /// `initialBoard`) shows its board without touching this, so ⌘⇧V still lands
    /// where the user left off.
    @AppStorage("pickerActiveBoard") private var savedBoard: String = BoardFilter.all
    @State private var activeBoard: String = BoardFilter.all
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
        [BoardFilter.all, BoardFilter.favorites] + store.pinboards.map(\.id)
    }

    /// Switch boards from a click or the Tab key — a deliberate choice, so it becomes
    /// the board the next plain summon opens on.
    private func selectBoard(_ id: String) {
        activeBoard = id
        savedBoard = id
        selectedIndex = 0
    }

    /// What to say when the list comes back empty — the Favorites tab needs to teach
    /// the gesture, since an empty one usually means "you haven't starred anything".
    private var emptyMessage: String {
        if activeBoard == BoardFilter.favorites && searchText.isEmpty {
            return store.favoriteCount == 0
                ? "No favorites yet — press ⌘D on a clip to star it"
                : "No favorites of this type"
        }
        return activeBoard == BoardFilter.all ? "No clips found" : "No clips in this board"
    }

    private func computeItems() -> [CopibaraItem] {
        var result: [CopibaraItem]
        switch activeBoard {
        case BoardFilter.all:       result = store.items
        case BoardFilter.favorites: result = store.items.filter(\.isFavorite)
        default:                    result = store.items.filter { $0.boardId == activeBoard }
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
                        isActive: activeBoard == BoardFilter.all
                    ) {
                        selectBoard(BoardFilter.all)
                    }

                    // Favourites — a view across every board, not a board of its own,
                    // so it sits with "All" ahead of the real pinboards.
                    BoardTab(
                        label: "Favorites",
                        icon: "star.fill",
                        isActive: activeBoard == BoardFilter.favorites,
                        tint: .favoriteAccent,
                        badge: store.favoriteCount
                    ) {
                        selectBoard(BoardFilter.favorites)
                    }

                    // Pinboard tabs
                    ForEach(store.pinboards, id: \.id) { board in
                        BoardTab(
                            label: board.name,
                            icon: board.icon,
                            isActive: activeBoard == board.id
                        ) {
                            selectBoard(board.id)
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
                    Text(activeBoard == BoardFilter.favorites ? "⭐️" : "📋")
                        .font(.system(size: 28))
                    Text(emptyMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.appTextSecondary)
                        .multilineTextAlignment(.center)
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
                                    isFavorite: item.isFavorite,
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
                HintLabel(keys: "⌘D", label: "star")
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
            // A targeted summon shows its board for this session only; otherwise pick
            // up where the user left off. Either way, never land on a board that was
            // deleted since last time.
            let wanted = initialBoard ?? savedBoard
            activeBoard = allTabs.contains(wanted) ? wanted : BoardFilter.all
            activeTypeFilter = initialTypeFilter
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

    /// Keep the cursor inside a list that just shrank under it.
    private func clampSelection(to count: Int) {
        guard count > 0 else { resetSelectionToTop(); return }
        if selectedIndex >= count {
            selectedIndex = count - 1
            selectionAnchor = selectedIndex
            selectedIndices = [selectedIndex]
        } else {
            selectedIndices = selectedIndices.filter { $0 < count }
            if selectedIndices.isEmpty { selectedIndices = [selectedIndex] }
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
            case 2: // 'D' — ⌘D stars/unstars the focused row without leaving the picker
                if event.modifierFlags.contains(.command) {
                    let currentItems = computeItems()
                    let ids = selectedIndices.count > 1
                        ? Set(selectedIndices.compactMap {
                            currentItems.indices.contains($0) ? currentItems[$0].id : nil
                          })
                        : Set(currentItems.indices.contains(selectedIndex)
                              ? [currentItems[selectedIndex].id] : [])
                    guard !ids.isEmpty else { return nil }
                    // Mixed selection stars everything; an all-starred one unstars.
                    let allStarred = ids.allSatisfy { store.isFavorite(id: $0) }
                    store.setFavorite(!allStarred, ids: ids)
                    // Unstarring from the Favorites view removes those rows from under
                    // the cursor, so pull it back into the list that's left.
                    clampSelection(to: computeItems().count)
                    return nil
                }
                return event
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
                        selectBoard(allTabs[(idx + 1) % allTabs.count])
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
    /// Colour when active. Defaults to the app blue; Favorites uses amber so the tab
    /// reads as starred even out of the corner of your eye.
    var tint: Color = .appPrimary
    /// Optional count shown beside the label. Nil or 0 renders nothing.
    var badge: Int? = nil
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

                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(isActive ? tint : Color.appTextTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(tint.opacity(isActive ? 0.18 : 0.10)))
                }
            }
            .foregroundStyle(isActive ? tint : Color.appTextSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? tint.opacity(0.12) : (isHovering ? Color.appSurfaceHover : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? tint.opacity(0.25) : Color.clear, lineWidth: 0.5)
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
    var isFavorite: Bool = false
    var yapivOrange: Color = Color.orange

    /// Same language as the grid card: amber for starred, orange for voice, green for
    /// foraged. A star is a deliberate choice, so it outranks where the clip came from.
    private var accent: Color? {
        if isFavorite { return .favoriteAccent }
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
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(Color.favoriteAccent)
                    }
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
