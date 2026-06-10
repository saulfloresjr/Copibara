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
    let onDismiss: () -> Void

    @State private var selectedIndex: Int = 0
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
                                    isSelected: index == selectedIndex,
                                    isYapivo: item.boardId == "yapivo",
                                    yapivOrange: yapivOrange
                                )
                                .id("\(activeBoard)-\(item.id)")
                                .onTapGesture {
                                    onSelect(item)
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
                HintLabel(keys: "↩", label: "paste")
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
            selectedIndex = 0
        }
        .onChange(of: activeTypeFilter) {
            selectedIndex = 0
        }
        .onChange(of: pickerSizeRaw) { _, newValue in
            // Resize the hosting FloatingPanel and keep it on screen
            if let size = PickerSize(rawValue: newValue),
               let panel = NSApp.windows.compactMap({ $0 as? FloatingPanel }).first(where: { $0.isVisible }) {
                panel.repositionOnScreen(newSize: NSSize(width: size.width, height: size.height))
            }
        }
    }

    // MARK: - Key Monitor

    private func installKeyMonitor() {
        // Local monitor: handles all keys when the picker is focused
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case 126: // ↑ arrow
                if selectedIndex > 0 { selectedIndex -= 1 }
                return nil
            case 125: // ↓ arrow
                let currentItems = computeItems()
                if selectedIndex < currentItems.count - 1 { selectedIndex += 1 }
                return nil
            case 36: // Return
                let currentItems = computeItems()
                if !currentItems.isEmpty && selectedIndex < currentItems.count {
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
    var isYapivo: Bool = false
    var yapivOrange: Color = Color.orange

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Type indicator — orange for Yapivo
            Circle()
                .fill(isYapivo ? yapivOrange : item.type.color)
                .frame(width: 6, height: 6)

            // Content preview
            VStack(alignment: .leading, spacing: 2) {
                if item.type == .image, let image = loadImage() {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.appBorder, lineWidth: 0.5)
                        )
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
                    }
                    Text("\(item.type.label) · \(item.createdAt.timeAgoDisplay())")
                        .font(.system(size: 10))
                        .foregroundStyle(isYapivo ? yapivOrange.opacity(0.7) : Color.appTextTertiary)
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
                    isSelected ? Color.appPrimary.opacity(0.3)
                    : isYapivo ? yapivOrange.opacity(0.3)
                    : Color.clear,
                    lineWidth: isYapivo && !isSelected ? 1 : (isSelected ? 1 : 0)
                )
        )
        .shadow(
            color: isYapivo ? yapivOrange.opacity(0.15) : Color.clear,
            radius: isYapivo ? 4 : 0,
            y: 0
        )
        .padding(.horizontal, 4)
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
    }

    private func loadImage() -> NSImage? {
        guard let fileName = item.imageFileName else { return nil }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let imagePath = appSupport
            .appendingPathComponent("CopibaraManager", isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent(fileName)
        return NSImage(contentsOf: imagePath)
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
