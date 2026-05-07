import AppKit
import ApplicationServices
import CoreGraphics

enum VisibilityMode: String, CaseIterable, Codable {
    case alwaysShown
    case floatingShelf
    case alwaysHidden

    var label: String {
        switch self {
        case .alwaysShown: return "Always shown"
        case .floatingShelf: return "Floating shelf"
        case .alwaysHidden: return "Always hidden"
        }
    }
}

struct ManagedMenuBarItem: Identifiable, Equatable {
    let id: String
    let owner: String
    let name: String
    let windowNumber: CGWindowID
    let bounds: CGRect
    let image: NSImage?

    var displayName: String {
        if name.isEmpty { return owner }
        return "\(owner) — \(name)"
    }
}

final class Preferences {
    private enum Key {
        static let collapsed = "collapsed.v1"
        static let spacerWidth = "spacerWidth.v1"
        static let alwaysHiddenEnabled = "alwaysHiddenEnabled.v1"
        static let autoCollapseSeconds = "autoCollapseSeconds.v1"
        static let itemModes = "itemModes.v2"
        static let useAdvancedRouting = "useAdvancedRouting.v2"
    }

    var collapsed: Bool {
        get { UserDefaults.standard.object(forKey: Key.collapsed) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: Key.collapsed) }
    }

    var spacerWidth: CGFloat {
        get {
            let value = UserDefaults.standard.double(forKey: Key.spacerWidth)
            return value > 0 ? CGFloat(value) : 460
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: Key.spacerWidth) }
    }

    var alwaysHiddenEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.alwaysHiddenEnabled) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: Key.alwaysHiddenEnabled) }
    }

    var autoCollapseSeconds: TimeInterval {
        get {
            let value = UserDefaults.standard.double(forKey: Key.autoCollapseSeconds)
            return value > 0 ? value : 8
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.autoCollapseSeconds) }
    }

    var useAdvancedRouting: Bool {
        get { UserDefaults.standard.object(forKey: Key.useAdvancedRouting) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.useAdvancedRouting) }
    }

    var itemModes: [String: VisibilityMode] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Key.itemModes),
                  let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
            return raw.compactMapValues(VisibilityMode.init(rawValue:))
        }
        set {
            let raw = newValue.mapValues(\.rawValue)
            if let data = try? JSONEncoder().encode(raw) {
                UserDefaults.standard.set(data, forKey: Key.itemModes)
            }
        }
    }

    func mode(for item: ManagedMenuBarItem) -> VisibilityMode {
        itemModes[item.id] ?? .alwaysShown
    }

    func setMode(_ mode: VisibilityMode, for item: ManagedMenuBarItem) {
        var modes = itemModes
        modes[item.id] = mode
        itemModes = modes
    }
}

final class PermissionManager {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static var hasScreenCaptureAccess: Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    static func requestScreenCapture() {
        if #available(macOS 10.15, *) {
            CGRequestScreenCaptureAccess()
        }
    }
}

final class MenuBarItemScanner {
    private let ignoredOwners = ["BarShelf", "Window Server"]

    func scan() -> [ManagedMenuBarItem] {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return infoList.compactMap(item(from:))
            .filter { !ignoredOwners.contains($0.owner) }
            .sorted { lhs, rhs in
                if lhs.bounds.minY == rhs.bounds.minY { return lhs.bounds.minX < rhs.bounds.minX }
                return lhs.bounds.minY < rhs.bounds.minY
            }
    }

    private func item(from info: [String: Any]) -> ManagedMenuBarItem? {
        guard let layer = info[kCGWindowLayer as String] as? Int,
              let owner = info[kCGWindowOwnerName as String] as? String,
              let windowNumber = info[kCGWindowNumber as String] as? UInt32,
              let boundsInfo = info[kCGWindowBounds as String] as? [String: Any] else { return nil }

        let bounds = CGRect(
            x: Self.number(boundsInfo["X"]),
            y: Self.number(boundsInfo["Y"]),
            width: Self.number(boundsInfo["Width"]),
            height: Self.number(boundsInfo["Height"])
        )

        guard isLikelyStatusItem(layer: layer, bounds: bounds) else { return nil }

        let name = info[kCGWindowName as String] as? String ?? ""
        let stableName = name.isEmpty ? "status-item" : name
        let id = "\(owner)|\(stableName)|\(Int(bounds.minX.rounded()))"
        let image = capture(windowNumber: CGWindowID(windowNumber), bounds: bounds)

        return ManagedMenuBarItem(id: id, owner: owner, name: name, windowNumber: CGWindowID(windowNumber), bounds: bounds, image: image)
    }

    private static func number(_ value: Any?) -> CGFloat {
        if let value = value as? CGFloat { return value }
        if let value = value as? Double { return CGFloat(value) }
        if let value = value as? Int { return CGFloat(value) }
        if let value = value as? NSNumber { return CGFloat(truncating: value) }
        return 0
    }

    private func isLikelyStatusItem(layer: Int, bounds: CGRect) -> Bool {
        // Menu bar extras commonly appear as CGWindow layer 25 with menu-bar-height bounds.
        // The height range intentionally allows recent macOS/menu-scale differences.
        guard layer == 25 else { return false }
        guard bounds.height >= 18 && bounds.height <= 34 else { return false }
        guard bounds.width >= 6 && bounds.width <= 180 else { return false }
        guard bounds.minY <= 40 else { return false }
        return true
    }

    private func capture(windowNumber: CGWindowID, bounds: CGRect) -> NSImage? {
        guard PermissionManager.hasScreenCaptureAccess else { return nil }
        guard let cgImage = CGWindowListCreateImage(bounds, .optionIncludingWindow, windowNumber, [.boundsIgnoreFraming, .nominalResolution]) else { return nil }
        return NSImage(cgImage: cgImage, size: bounds.size)
    }
}

final class MaskOverlayController {
    private var overlays: [String: NSPanel] = [:]

    func apply(items: [ManagedMenuBarItem], preferences: Preferences) {
        let hiddenIds = Set(items.filter { preferences.mode(for: $0) != .alwaysShown }.map(\.id))

        for item in items where hiddenIds.contains(item.id) {
            let frame = appKitFrame(forCGWindowBounds: item.bounds)
            if overlays[item.id] == nil {
                overlays[item.id] = makeOverlay(bounds: frame)
            }
            overlays[item.id]?.setFrame(frame, display: true)
            overlays[item.id]?.orderFrontRegardless()
        }

        for (id, panel) in overlays where !hiddenIds.contains(id) {
            panel.orderOut(nil)
            overlays[id] = nil
        }
    }

    func temporarilyReveal(id: String, action: () -> Void) {
        overlays[id]?.orderOut(nil)
        action()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.overlays[id]?.orderFrontRegardless()
        }
    }

    private func appKitFrame(forCGWindowBounds bounds: CGRect) -> CGRect {
        let screens = NSScreen.screens
        let maxY = screens.map { $0.frame.maxY }.max() ?? (NSScreen.main?.frame.maxY ?? 900)
        return CGRect(x: bounds.minX, y: maxY - bounds.maxY, width: bounds.width, height: bounds.height)
    }

    private func makeOverlay(bounds: CGRect) -> NSPanel {
        let panel = NSPanel(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = false
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear

        let view = NSVisualEffectView(frame: NSRect(origin: .zero, size: bounds.size))
        view.autoresizingMask = [.width, .height]
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        panel.contentView = view
        return panel
    }
}

final class FloatingShelfWindowController: NSObject {
    private var panel: NSPanel?
    private weak var controller: BarShelfController?

    init(controller: BarShelfController) {
        self.controller = controller
    }

    func update(items: [ManagedMenuBarItem], preferences: Preferences) {
        let shelfItems = items.filter { preferences.mode(for: $0) == .floatingShelf }
        guard !shelfItems.isEmpty else {
            panel?.orderOut(nil)
            return
        }

        if panel == nil { panel = makePanel() }
        guard let panel else { return }

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

        for item in shelfItems {
            let button = NSButton()
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.toolTip = item.displayName
            button.target = controller
            button.action = #selector(BarShelfController.floatingShelfItemClicked(_:))
            button.identifier = NSUserInterfaceItemIdentifier(item.id)
            button.setButtonType(.momentaryChange)
            if let image = item.image {
                image.size = NSSize(width: min(max(item.bounds.width, 18), 28), height: min(max(item.bounds.height, 18), 24))
                button.image = image
            } else {
                button.title = String(item.owner.prefix(1)).uppercased()
                button.font = .systemFont(ofSize: 13, weight: .semibold)
            }
            stack.addArrangedSubview(button)
        }

        let width = max(72, CGFloat(shelfItems.count) * 34 + 24)
        let height: CGFloat = 46
        stack.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let effect = NSVisualEffectView(frame: stack.frame)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 13
        effect.layer?.masksToBounds = true
        effect.addSubview(stack)

        panel.contentView = effect
        panel.setFrame(frame(width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 120, height: 46), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        return panel
    }

    private func frame(width: CGFloat, height: CGFloat) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - 88
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

final class BarShelfController: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private let scanner = MenuBarItemScanner()
    private let overlays = MaskOverlayController()
    private var floatingShelf: FloatingShelfWindowController!
    private var managedItems: [ManagedMenuBarItem] = []

    private var toggleItem: NSStatusItem!
    private var separatorItem: NSStatusItem!
    private var shelfSpacerItem: NSStatusItem!
    private var alwaysHiddenSeparatorItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var settingsWindow: NSWindow?
    private var scanTimer: Timer?
    private var collapseTimer: Timer?
    private var shelfVisible = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        floatingShelf = FloatingShelfWindowController(controller: self)
        createStatusItems()
        applyLegacyState(animated: false)
        rescanAndApply()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.rescanAndApply()
        }
    }

    private func createStatusItems() {
        alwaysHiddenSeparatorItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureButton(alwaysHiddenSeparatorItem.button, title: "▥", help: "BarShelf always-hidden separator. Hold Command and drag menu bar icons left of this marker.")

        shelfSpacerItem = NSStatusBar.system.statusItem(withLength: 1)
        configureButton(shelfSpacerItem.button, title: "", help: "BarShelf hidden shelf spacer")
        shelfSpacerItem.button?.isEnabled = false

        separatorItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureButton(separatorItem.button, title: "│", help: "BarShelf separator. Hold Command and drag menu bar icons left of this marker to hide them when collapsed.")

        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureButton(toggleItem.button, title: "▦", help: "Show BarShelf hidden icons")
        toggleItem.button?.target = self
        toggleItem.button?.action = #selector(toggleShelf)
        toggleItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        statusMenu = NSMenu()
        statusMenu.addItem(NSMenuItem(title: "Show / hide hidden icons", action: #selector(toggleShelfFromMenu), keyEquivalent: ""))
        statusMenu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        statusMenu.addItem(NSMenuItem(title: "Rescan menu bar items", action: #selector(rescanFromMenu), keyEquivalent: "r"))
        statusMenu.addItem(NSMenuItem(title: "Request permissions", action: #selector(requestPermissions), keyEquivalent: ""))
        statusMenu.addItem(NSMenuItem(title: "How to Use", action: #selector(showHelp), keyEquivalent: "?"))
        statusMenu.addItem(.separator())
        statusMenu.addItem(NSMenuItem(title: "Quit BarShelf", action: #selector(quit), keyEquivalent: "q"))
        statusMenu.items.forEach { $0.target = self }
    }

    private func configureButton(_ button: NSStatusBarButton?, title: String, help: String) {
        button?.title = title
        button?.toolTip = help
        button?.font = .systemFont(ofSize: 15, weight: .medium)
    }

    @objc private func toggleShelf() {
        if NSApp.currentEvent?.type == .rightMouseUp, let button = toggleItem.button {
            statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
            return
        }
        shelfVisible.toggle()
        rescanAndApply()
    }

    @objc private func toggleShelfFromMenu() {
        shelfVisible.toggle()
        rescanAndApply()
    }

    private func applyLegacyState(animated: Bool) {
        let collapsed = preferences.collapsed
        let width = collapsed ? preferences.spacerWidth : 1
        shelfSpacerItem.length = width
        alwaysHiddenSeparatorItem.isVisible = preferences.alwaysHiddenEnabled

        collapseTimer?.invalidate()
        if !collapsed {
            collapseTimer = Timer.scheduledTimer(withTimeInterval: preferences.autoCollapseSeconds, repeats: false) { [weak self] _ in
                self?.preferences.collapsed = true
                self?.applyLegacyState(animated: true)
            }
        }
    }

    @objc private func rescanFromMenu() {
        rescanAndApply()
        rebuildSettingsWindowIfOpen()
    }

    private func rescanAndApply() {
        managedItems = scanner.scan()
        guard preferences.useAdvancedRouting else {
            floatingShelf.hide()
            return
        }
        overlays.apply(items: managedItems, preferences: preferences)
        if shelfVisible {
            floatingShelf.update(items: managedItems, preferences: preferences)
            toggleItem.button?.title = "▦"
            toggleItem.button?.toolTip = "Hide BarShelf hidden icons"
        } else {
            floatingShelf.hide()
            toggleItem.button?.title = "▦"
            toggleItem.button?.toolTip = "Show BarShelf hidden icons"
        }
    }

    @objc func floatingShelfItemClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let item = managedItems.first(where: { $0.id == id }) else { return }

        overlays.temporarilyReveal(id: id) {
            click(item: item)
        }
    }

    private func click(item: ManagedMenuBarItem) {
        guard PermissionManager.isAccessibilityTrusted else {
            requestPermissions()
            return
        }

        let point = CGPoint(x: item.bounds.midX, y: item.bounds.midY)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    @objc private func openSettings() {
        buildSettingsWindow()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildSettingsWindow() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 560))

        let title = NSTextField(labelWithString: "BarShelf")
        title.font = .systemFont(ofSize: 26, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let instructions = NSTextField(wrappingLabelWithString: "Assign each detected menu bar icon to Always shown, Floating shelf, or Always hidden. BarShelf uses macOS Accessibility and screen capture permissions to identify icons, mask originals, and forward clicks from the floating shelf.")
        instructions.textColor = .secondaryLabelColor
        instructions.translatesAutoresizingMaskIntoConstraints = false

        let advanced = NSButton(checkboxWithTitle: "Enable per-item advanced routing", target: self, action: #selector(advancedRoutingChanged(_:)))
        advanced.state = preferences.useAdvancedRouting ? .on : .off
        advanced.translatesAutoresizingMaskIntoConstraints = false

        let permissionButton = NSButton(title: "Request permissions", target: self, action: #selector(requestPermissions))
        permissionButton.translatesAutoresizingMaskIntoConstraints = false

        let rescanButton = NSButton(title: "Rescan", target: self, action: #selector(rescanFromSettings))
        rescanButton.translatesAutoresizingMaskIntoConstraints = false

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 8
        rows.translatesAutoresizingMaskIntoConstraints = false

        if managedItems.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: "No third-party menu bar items detected yet. Make sure Screen Recording permission is granted, then click Rescan.")
            empty.textColor = .secondaryLabelColor
            rows.addArrangedSubview(empty)
        } else {
            for item in managedItems {
                rows.addArrangedSubview(row(for: item))
            }
        }

        let scroll = NSScrollView()
        scroll.documentView = rows
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let legacyTitle = NSTextField(labelWithString: "Fallback separator mode")
        legacyTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        legacyTitle.translatesAutoresizingMaskIntoConstraints = false

        let widthLabel = NSTextField(labelWithString: "Hidden shelf width")
        widthLabel.translatesAutoresizingMaskIntoConstraints = false
        let widthSlider = NSSlider(value: Double(preferences.spacerWidth), minValue: 180, maxValue: 900, target: self, action: #selector(widthChanged(_:)))
        widthSlider.translatesAutoresizingMaskIntoConstraints = false

        let alwaysHidden = NSButton(checkboxWithTitle: "Show always-hidden separator", target: self, action: #selector(alwaysHiddenChanged(_:)))
        alwaysHidden.state = preferences.alwaysHiddenEnabled ? .on : .off
        alwaysHidden.translatesAutoresizingMaskIntoConstraints = false

        [title, instructions, advanced, permissionButton, rescanButton, scroll, legacyTitle, widthLabel, widthSlider, alwaysHidden].forEach(content.addSubview)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            instructions.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            instructions.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            instructions.trailingAnchor.constraint(equalTo: title.trailingAnchor),

            advanced.topAnchor.constraint(equalTo: instructions.bottomAnchor, constant: 18),
            advanced.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            permissionButton.centerYAnchor.constraint(equalTo: advanced.centerYAnchor),
            permissionButton.leadingAnchor.constraint(equalTo: advanced.trailingAnchor, constant: 18),
            rescanButton.centerYAnchor.constraint(equalTo: advanced.centerYAnchor),
            rescanButton.leadingAnchor.constraint(equalTo: permissionButton.trailingAnchor, constant: 10),

            scroll.topAnchor.constraint(equalTo: advanced.bottomAnchor, constant: 18),
            scroll.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 250),

            legacyTitle.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 20),
            legacyTitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),

            widthLabel.topAnchor.constraint(equalTo: legacyTitle.bottomAnchor, constant: 14),
            widthLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            widthSlider.centerYAnchor.constraint(equalTo: widthLabel.centerYAnchor),
            widthSlider.leadingAnchor.constraint(equalTo: widthLabel.trailingAnchor, constant: 18),
            widthSlider.trailingAnchor.constraint(equalTo: title.trailingAnchor),

            alwaysHidden.topAnchor.constraint(equalTo: widthLabel.bottomAnchor, constant: 18),
            alwaysHidden.leadingAnchor.constraint(equalTo: title.leadingAnchor)
        ])

        settingsWindow = NSWindow(contentRect: content.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        settingsWindow?.title = "BarShelf Settings"
        settingsWindow?.contentView = content
        settingsWindow?.center()
    }

    private func row(for item: ManagedMenuBarItem) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.frame = NSRect(x: 0, y: 0, width: 660, height: 32)

        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = item.image
        imageView.imageScaling = .scaleProportionallyDown

        let label = NSTextField(labelWithString: item.displayName)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.widthAnchor.constraint(equalToConstant: 360).isActive = true

        let popup = NSPopUpButton()
        popup.translatesAutoresizingMaskIntoConstraints = false
        for mode in VisibilityMode.allCases { popup.addItem(withTitle: mode.label) }
        popup.selectItem(withTitle: preferences.mode(for: item).label)
        popup.target = self
        popup.action = #selector(modeChanged(_:))
        popup.identifier = NSUserInterfaceItemIdentifier(item.id)
        popup.widthAnchor.constraint(equalToConstant: 170).isActive = true

        row.addArrangedSubview(imageView)
        row.addArrangedSubview(label)
        row.addArrangedSubview(popup)
        return row
    }

    private func rebuildSettingsWindowIfOpen() {
        guard settingsWindow?.isVisible == true else { return }
        buildSettingsWindow()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        guard let id = sender.identifier?.rawValue,
              let item = managedItems.first(where: { $0.id == id }),
              let selected = sender.selectedItem?.title,
              let mode = VisibilityMode.allCases.first(where: { $0.label == selected }) else { return }
        preferences.setMode(mode, for: item)
        rescanAndApply()
    }

    @objc private func advancedRoutingChanged(_ sender: NSButton) {
        preferences.useAdvancedRouting = sender.state == .on
        rescanAndApply()
    }

    @objc private func rescanFromSettings() {
        rescanAndApply()
        rebuildSettingsWindowIfOpen()
    }

    @objc private func requestPermissions() {
        PermissionManager.requestAccessibility()
        PermissionManager.requestScreenCapture()
        showPermissionHelpIfNeeded()
    }

    private func showPermissionHelpIfNeeded() {
        guard !PermissionManager.isAccessibilityTrusted || !PermissionManager.hasScreenCaptureAccess else { return }
        let alert = NSAlert()
        alert.messageText = "BarShelf needs macOS permissions"
        alert.informativeText = "Enable Accessibility so BarShelf can forward clicks from the floating shelf. Enable Screen Recording so it can capture menu bar icon images. After granting permissions, quit and reopen BarShelf, then click Rescan."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func widthChanged(_ sender: NSSlider) {
        preferences.spacerWidth = CGFloat(sender.doubleValue)
        applyLegacyState(animated: false)
    }

    @objc private func alwaysHiddenChanged(_ sender: NSButton) {
        preferences.alwaysHiddenEnabled = sender.state == .on
        applyLegacyState(animated: false)
    }

    @objc private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "How BarShelf works"
        alert.informativeText = "BarShelf’s own ▦ icon always stays in the menu bar. Click it to show or hide the floating shelf of items routed to Floating shelf mode. Use Settings to route detected icons into one of three modes: Always shown, Floating shelf, or Always hidden. Floating/hidden items are visually masked in the menu bar. Floating shelf items are shown in a translucent shelf below the menu bar and click through to the original item.\n\nIf an item cannot be detected reliably, use the fallback separator mode: hold Command (⌘), drag icons left of BarShelf's │ separator, then collapse the shelf."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = BarShelfController()
app.delegate = delegate
app.run()
