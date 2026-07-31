import SwiftUI

struct ContentView: View {
    @Bindable var store: CopibaraStore
    var onPasteItem: ((CopibaraItem) -> Void)? = nil

    @State private var searchText = ""
    @State private var selectedItemIds: Set<Int> = []
    @State private var lastClickedId: Int?
    @State private var showNewBoardSheet = false
    @State private var showAddItemSheet = false
    @State private var showClearConfirm = false
    @State private var boardToDelete: Pinboard?
    @State private var boardToClear: Pinboard?
    @State private var showClearAllBoardsConfirm = false
    @State private var activeTypeFilter: ContentType? = nil
    @State private var keyMonitor: Any?
    @State private var globalKeyMonitor: Any?

    /// Whether any overlay modal is showing.
    private var isModalOpen: Bool {
        showNewBoardSheet || showAddItemSheet || showClearConfirm || boardToDelete != nil || boardToClear != nil || showClearAllBoardsConfirm
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                header

                // Pinboard Tabs
                PinboardTabsView(store: store, showNewBoardSheet: $showNewBoardSheet, boardToDelete: $boardToDelete)

                // Main Area
                CopibaraGridView(
                    store: store,
                    searchText: searchText,
                    selectedItemIds: $selectedItemIds,
                    lastClickedId: $lastClickedId,
                    activeTypeFilter: $activeTypeFilter,
                    onDoubleClick: { item in
                        onPasteItem?(item)
                    },
                    onPasteItem: { item in
                        onPasteItem?(item)
                    }
                )
                .overlay(alignment: .trailing) {
                    // Detail panel overlays the grid instead of resizing it
                    if selectedItemIds.count == 1,
                       let id = selectedItemIds.first,
                       let item = store.item(for: id) {
                        DetailPanelView(
                            item: item,
                            onCopy: {
                                store.copyToClipboard(id: id)
                            },
                            onDelete: {
                                selectedItemIds.removeAll()
                                store.deleteItem(id: id)
                            },
                            onClose: {
                                selectedItemIds.removeAll()
                            },
                            onSaveImage: {
                                store.exportImage(for: id)
                            }
                        )
                    } else if selectedItemIds.count > 1 {
                        BulkActionBar(
                            selectedCount: selectedItemIds.count,
                            onCopyAll: {
                                store.copyItemsToClipboard(ids: selectedItemIds)
                            },
                            onDeleteAll: {
                                store.deleteItems(ids: selectedItemIds)
                                selectedItemIds.removeAll()
                            },
                            onDeselectAll: {
                                selectedItemIds.removeAll()
                                lastClickedId = nil
                            }
                        )
                    }
                }
            }

            // Inline overlay modals (avoids .sheet() crash in MenuBarExtra)
            if showNewBoardSheet {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showNewBoardSheet = false }

                NewPinboardSheet(isPresented: $showNewBoardSheet) { name, icon in
                    store.addPinboard(name: name, icon: icon)
                    store.activeBoard = store.pinboards.last?.id ?? "clipboard"
                }
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 4)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            if showAddItemSheet {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showAddItemSheet = false }

                AddItemSheet(isPresented: $showAddItemSheet) { content in
                    store.addItem(content: content)
                }
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 4)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            if showClearConfirm {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showClearConfirm = false }

                VStack(spacing: Spacing.base) {
                    Text("Clear All Items?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appTextPrimary)

                    Text("This will delete all items in the current board. This can't be undone.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appTextSecondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: Spacing.sm) {
                        Button("Cancel") {
                            showClearConfirm = false
                        }

                        Button("Clear All") {
                            store.clearAll()
                            showClearConfirm = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding(Spacing.xl)
                .frame(width: 280)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 4)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            if let board = boardToDelete {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { boardToDelete = nil }

                VStack(spacing: Spacing.base) {
                    Text("Delete \"\(board.name)\"?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appTextPrimary)

                    Text("All items in this board will be permanently deleted.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appTextSecondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: Spacing.sm) {
                        Button("Cancel") {
                            boardToDelete = nil
                        }

                        Button("Delete") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                store.deletePinboard(id: board.id)
                            }
                            boardToDelete = nil
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding(Spacing.xl)
                .frame(width: 280)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 4)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            // Confirmation: clear a specific board (from All menu)
            if let board = boardToClear {
                let count = store.items.filter { $0.boardId == board.id }.count
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { boardToClear = nil }

                VStack(spacing: Spacing.base) {
                    Text("Clear \"\(board.name)\"?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appTextPrimary)

                    Text("This will delete all \(count) items in \(board.name). This can't be undone.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appTextSecondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: Spacing.sm) {
                        Button("Cancel") {
                            boardToClear = nil
                        }

                        Button("Clear \(board.name)") {
                            store.clearBoard(id: board.id)
                            boardToClear = nil
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding(Spacing.xl)
                .frame(width: 300)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 4)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            // Confirmation: clear EVERYTHING (nuclear option)
            if showClearAllBoardsConfirm {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showClearAllBoardsConfirm = false }

                VStack(spacing: Spacing.base) {
                    Text("⚠️ Clear Everything?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appTextPrimary)

                    Text("This will permanently delete \(store.items.count - store.pinnedCount) items across every board. This cannot be undone.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appTextSecondary)
                        .multilineTextAlignment(.center)

                    if store.pinnedCount > 0 {
                        Text("🌿 \(store.pinnedCount) collected \(store.pinnedCount == 1 ? "find" : "finds") will be kept — clear the Collected board directly to remove those.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.forageAccent)
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: Spacing.sm) {
                        Button("Cancel") {
                            showClearAllBoardsConfirm = false
                        }

                        Button("Delete Everything") {
                            store.clearAllBoards()
                            showClearAllBoardsConfirm = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding(Spacing.xl)
                .frame(width: 320)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 4)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showNewBoardSheet)
        .animation(.easeInOut(duration: 0.2), value: showAddItemSheet)
        .animation(.easeInOut(duration: 0.2), value: showClearConfirm)
        .animation(.easeInOut(duration: 0.2), value: boardToDelete?.id)
        .animation(.easeInOut(duration: 0.2), value: boardToClear?.id)
        .animation(.easeInOut(duration: 0.2), value: showClearAllBoardsConfirm)
        .background(Color.appBackground)
        .frame(width: 720, height: 520)
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                Text(toast)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.82)))
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: store.toast)
        .onChange(of: store.toast) { _, newValue in
            guard newValue != nil, newValue != "Removing background…" else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                if store.toast == newValue { store.toast = nil }
            }
        }
        .onKeyPress(.return) {
            // Enter: paste the single selected item
            guard !isModalOpen else { return .ignored }
            guard selectedItemIds.count == 1,
                  let id = selectedItemIds.first,
                  let item = store.item(for: id) else {
                // If nothing selected, select+paste the first item
                let items = store.filteredItems(search: searchText)
                guard let first = items.first else { return .ignored }
                onPasteItem?(first)
                return .handled
            }
            onPasteItem?(item)
            return .handled
        }
        .onKeyPress(.downArrow) {
            // ↓ move selection to next item
            guard !isModalOpen else { return .ignored }
            let items = store.filteredItems(search: searchText)
            guard !items.isEmpty else { return .ignored }

            if selectedItemIds.isEmpty {
                // Nothing selected → select first item
                let firstId = items[0].id
                withAnimation(.easeInOut(duration: 0.1)) {
                    selectedItemIds = [firstId]
                    lastClickedId = firstId
                }
            } else if selectedItemIds.count == 1,
                      let currentId = selectedItemIds.first,
                      let currentIdx = items.firstIndex(where: { $0.id == currentId }),
                      currentIdx < items.count - 1 {
                // Move to next item
                let nextId = items[currentIdx + 1].id
                withAnimation(.easeInOut(duration: 0.1)) {
                    selectedItemIds = [nextId]
                    lastClickedId = nextId
                }
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            // ↑ move selection to previous item
            guard !isModalOpen else { return .ignored }
            let items = store.filteredItems(search: searchText)
            guard !items.isEmpty else { return .ignored }

            if selectedItemIds.isEmpty {
                // Nothing selected → select last item
                let lastId = items[items.count - 1].id
                withAnimation(.easeInOut(duration: 0.1)) {
                    selectedItemIds = [lastId]
                    lastClickedId = lastId
                }
            } else if selectedItemIds.count == 1,
                      let currentId = selectedItemIds.first,
                      let currentIdx = items.firstIndex(where: { $0.id == currentId }),
                      currentIdx > 0 {
                // Move to previous item
                let prevId = items[currentIdx - 1].id
                withAnimation(.easeInOut(duration: 0.1)) {
                    selectedItemIds = [prevId]
                    lastClickedId = prevId
                }
            }
            return .handled
        }
        .onKeyPress(characters: .alphanumerics) { press in
            // ⌘A: select all visible items
            if press.characters == "a" && NSEvent.modifierFlags.contains(.command) {
                guard !isModalOpen else { return .ignored }
                let visibleItems = store.filteredItems(search: searchText)
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedItemIds = Set(visibleItems.map(\.id))
                }
                return .handled
            }
            return .ignored
        }
        .focusable()
        .onAppear {
            // Aggressively force the MenuBarExtra panel to become key window
            // for keyboard events — run repeatedly to survive focus changes
            for delay in [0.05, 0.15, 0.3] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    if let window = NSApp.windows.first(where: { $0.isVisible && $0.level.rawValue > 0 }) {
                        window.makeKey()
                    }
                }
            }
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    // MARK: - Header

    /// App logo for the header — the capybara app icon embedded as base64 so it shows
    /// in both `swift run` (dev) and the built .app, instead of falling back to "C".
    static let appLogo: NSImage? = {
        // Shipped .app: AppIcon.icns lives in the bundle's Resources.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) { return img }
        // Dev fallback: an embedded copy of the icon.
        let base64 = "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"
        return Data(base64Encoded: base64).flatMap { NSImage(data: $0) }
    }()

    /// Launch the on-screen element picker, then drop the cutout on the clipboard.
    private func grabElement() {
        ScreenElementPicker.shared.start(
            status: { store.toast = $0 },
            completion: { data in
                guard let data else { return }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setData(data, forType: .png)
                let dims = NSBitmapImageRep(data: data).map { " (\($0.pixelsWide)×\($0.pixelsHigh))" } ?? ""
                store.toast = "Element grabbed\(dims) — paste anywhere, also saved as a clip"
            }
        )
    }

    // MARK: - Forage Toggle

    private var forage: ForageMode { ForageMode.shared }

    /// Click toggles Forage mode; right-click opens its settings.
    ///
    /// A plain Button rather than a Menu: macOS renders menu labels with its own
    /// control tinting, which overrode `foregroundStyle` and left the leaf grey even
    /// while armed. The armed state has to be unmistakable, so the colour wins.
    private var forageButton: some View {
        Button {
            forage.toggle()
        } label: {
            Image(systemName: forage.isArmed ? "leaf.fill" : "leaf")
                .font(.system(size: 13, weight: forage.isArmed ? .semibold : .regular))
                .foregroundStyle(forage.isArmed ? Color.forageAccent : Color.appTextSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(forage.isArmed ? Color.forageAccent.opacity(0.18) : Color.appSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(forage.isArmed ? Color.forageAccent.opacity(0.55) : Color.clear,
                                lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Toggle("Auto-arm on allowlisted sites", isOn: Binding(
                get: { forage.autoArmEnabled },
                set: { forage.autoArmEnabled = $0 }
            ))
            Divider()
            Section("Auto-arm sites") {
                ForEach(ForageMode.knownSites, id: \.self) { site in
                    Toggle(site, isOn: Binding(
                        get: { forage.allowlist.contains(site) },
                        set: { _ in forage.toggleSite(site) }
                    ))
                }
            }
        }
        .help(forage.isArmed
              ? "Forage mode ON — captures go to Collected with their source (\(Shortcuts.forageDisplay)). Right-click for settings."
              : "Forage mode OFF — turn on to collect finds with their source (\(Shortcuts.forageDisplay)). Right-click for settings.")
    }

    private var header: some View {
        HStack(spacing: Spacing.base) {
            // Logo
            HStack(spacing: Spacing.sm) {
                if let icon = Self.appLogo {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                } else {
                    Text("C")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            LinearGradient(
                                colors: [Color.appPrimary, Color.appPrimaryHover],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }

                Text("Copibara")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.appTextPrimary)
            }

            // Search
            SearchBar(text: $searchText)

            // Actions
            HStack(spacing: Spacing.sm) {
                if store.activeBoard == "all" {
                    // "All" board: show a menu with per-board clear + nuclear option
                    Menu {
                        Section("Clear Board") {
                            ForEach(store.pinboards, id: \.id) { board in
                                let count = store.items.filter { $0.boardId == board.id }.count
                                Button {
                                    boardToClear = board
                                } label: {
                                    Label("\(board.icon) \(board.name) (\(count))", systemImage: "xmark.circle")
                                }
                                .disabled(count == 0)
                            }
                        }
                        Divider()
                        Button(role: .destructive) {
                            showClearAllBoardsConfirm = true
                        } label: {
                            Label("Clear Everything (\(store.items.count))", systemImage: "trash.fill")
                        }
                        .disabled(store.items.isEmpty)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.appTextSecondary)
                            .frame(width: 32, height: 32)
                            .background(Color.appSurfaceHover)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 32, height: 32)
                    .help("Clear boards…")
                } else {
                    // Specific board: single clear button
                    Button {
                        showClearConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.appTextSecondary)
                            .frame(width: 32, height: 32)
                            .background(Color.appSurfaceHover)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                    }
                    .buttonStyle(.plain)
                    .help("Clear All")
                }

                forageButton

                // Window capture — the same flow Yapivo triggers by voice, available
                // by hand so it's testable without the URL scheme / voice path.
                Button {
                    WindowCapturePicker.shared.capture(status: { store.toast = $0 })
                } label: {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appTextSecondary)
                        .frame(width: 28, height: 28)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                }
                .buttonStyle(.plain)
                .help("Screenshot a window — pick by number (voice-drivable via Yapivo)")

                Button {
                    grabElement()
                } label: {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appTextSecondary)
                        .frame(width: 28, height: 28)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                }
                .buttonStyle(.plain)
                .help("Grab an element from the screen")

                Button {
                    showAddItemSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Add")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize()          // never let "Add" wrap to "Ad / d"
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.appPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("Add Item")

                // Quit
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.appTextTertiary)
                        .frame(width: 32, height: 32)
                        .background(Color.appSurfaceHover)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                }
                .buttonStyle(.plain)
                .help("Quit Copibara")
            }
            // Adding the leaf left the action row fighting the search field for
            // width, and the loser was the "Add" label. Pin the row to its intrinsic
            // size so the search field absorbs any shortfall instead.
            .fixedSize()
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
        .background(Color.appSurface)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - NSEvent Key Monitor (Escape & Shift+Tab)

    private func installKeyMonitor() {
        removeKeyMonitor() // prevent duplicates

        // Local monitor: fires when this app is active and a window has key status
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch Int(event.keyCode) {
            case 53: // Escape
                return handleEscapeEvent()
            case 48: // Tab
                if mods.contains(.shift) {
                    handleShiftTab()
                    return nil  // consume the event
                }
                // Plain Tab: cycle boards
                handleTab()
                return nil  // consume — prevent focus navigation to search bar
            default:
                return event
            }
        }

        // Global monitor: catches Escape even when the MenuBarExtra panel
        // isn't key (e.g. focus went to another element or a child menu)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [self] event in
            if Int(event.keyCode) == 53 { // Escape
                DispatchQueue.main.async {
                    _ = self.handleEscapeEvent()
                }
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

    /// Handles Escape key with priority: modals → selection → close window.
    /// Returns nil if handled, the event otherwise.
    private func handleEscapeEvent() -> NSEvent? {
        // Force-resign first responder so the SearchBar's @FocusState
        // doesn't eat this Escape before we can act on it.
        // Without this, the user needs a double-tap: once to unfocus
        // the TextField, once to reach our handler.
        if let window = NSApp.keyWindow {
            window.makeFirstResponder(nil)
        }

        if boardToClear != nil {
            boardToClear = nil
            return nil
        }
        if showClearAllBoardsConfirm {
            showClearAllBoardsConfirm = false
            return nil
        }
        if boardToDelete != nil {
            boardToDelete = nil
            return nil
        }
        if showClearConfirm {
            showClearConfirm = false
            return nil
        }
        if showNewBoardSheet {
            showNewBoardSheet = false
            return nil
        }
        if showAddItemSheet {
            showAddItemSheet = false
            return nil
        }
        // Clear search text if present
        if !searchText.isEmpty {
            searchText = ""
            return nil
        }
        if !selectedItemIds.isEmpty {
            withAnimation { selectedItemIds.removeAll(); lastClickedId = nil }
            return nil
        }
        // Clear type filter if active
        if activeTypeFilter != nil {
            activeTypeFilter = nil
            return nil
        }
        // Nothing open — dismiss the MenuBarExtra window
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.className.contains("StatusBarWindow") || ($0.isVisible && $0.level.rawValue > 0) }) {
            window.orderOut(nil)
        }
        NSApp.deactivate()
        return nil
    }

    /// Cycles to the next board: all → board1 → board2 → … → all
    private func handleTab() {
        guard !isModalOpen else { return }
        let allTabs = ["all"] + store.pinboards.map(\.id)
        guard let idx = allTabs.firstIndex(of: store.activeBoard) else { return }
        let nextIdx = (idx + 1) % allTabs.count
        store.activeBoard = allTabs[nextIdx]
        selectedItemIds.removeAll()
    }

    /// Cycles the type filter: nil → .text → .code → .link → .image → nil
    private func handleShiftTab() {
        guard !isModalOpen else { return }
        let allTypes = ContentType.allCases
        if let current = activeTypeFilter,
           let idx = allTypes.firstIndex(of: current) {
            let nextIdx = idx + 1
            activeTypeFilter = nextIdx < allTypes.count ? allTypes[nextIdx] : nil
        } else {
            activeTypeFilter = allTypes.first
        }
        selectedItemIds.removeAll()
    }
}
