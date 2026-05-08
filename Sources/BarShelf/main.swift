import AppKit
import ApplicationServices
import Foundation
import BarShelfCore
import CoreGraphics
import ServiceManagement

struct ManagedMenuBarItem: Identifiable, Equatable {
    let id: String
    let owner: String
    let name: String
    let ownerPID: pid_t
    let bundleIdentifier: String?
    let windowNumber: CGWindowID
    let bounds: CGRect
    let image: NSImage?

    var displayName: String {
        MenuBarItemIdentity(owner: owner, name: name, roundedX: Int(bounds.minX.rounded())).displayName
    }

    func withName(_ newName: String) -> ManagedMenuBarItem {
        let resolvedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedName.isEmpty else { return self }
        return ManagedMenuBarItem(
            id: id,
            owner: owner,
            name: resolvedName,
            ownerPID: ownerPID,
            bundleIdentifier: bundleIdentifier,
            windowNumber: windowNumber,
            bounds: bounds,
            image: image
        )
    }

    func withImage(_ newImage: NSImage?) -> ManagedMenuBarItem {
        ManagedMenuBarItem(
            id: id,
            owner: owner,
            name: name,
            ownerPID: ownerPID,
            bundleIdentifier: bundleIdentifier,
            windowNumber: windowNumber,
            bounds: bounds,
            image: newImage ?? image
        )
    }
}

final class Preferences {
    private let store = BarShelfSettingsStore()
    private let defaults = BarShelfDefaults.store()

    var collapsed: Bool {
        get { defaults.object(forKey: BarShelfDefaults.Key.collapsed) as? Bool ?? false }
        set { defaults.set(newValue, forKey: BarShelfDefaults.Key.collapsed) }
    }

    var spacerWidth: CGFloat {
        get {
            let value = defaults.double(forKey: BarShelfDefaults.Key.spacerWidth)
            return value > 0 ? CGFloat(value) : 460
        }
        set { defaults.set(Double(newValue), forKey: BarShelfDefaults.Key.spacerWidth) }
    }

    var alwaysHiddenEnabled: Bool {
        get { defaults.object(forKey: BarShelfDefaults.Key.alwaysHiddenEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: BarShelfDefaults.Key.alwaysHiddenEnabled) }
    }

    var autoCollapseSeconds: TimeInterval {
        get {
            let value = defaults.double(forKey: BarShelfDefaults.Key.autoCollapseSeconds)
            return value > 0 ? value : 8
        }
        set { defaults.set(newValue, forKey: BarShelfDefaults.Key.autoCollapseSeconds) }
    }

    var useAdvancedRouting: Bool {
        get { store.useAdvancedRouting }
        set { store.useAdvancedRouting = newValue }
    }

    var shelfVisible: Bool {
        get { store.shelfVisible }
        set { store.shelfVisible = newValue }
    }

    var itemModes: [String: VisibilityMode] {
        get { store.itemModes }
        set { store.itemModes = newValue }
    }

    func order(for mode: VisibilityMode) -> [String] {
        store.order(for: mode)
    }

    func setOrder(_ ids: [String], for mode: VisibilityMode) {
        store.setOrder(ids, for: mode)
    }

    var setupCompleted: Bool {
        get { defaults.object(forKey: BarShelfDefaults.Key.setupCompleted) as? Bool ?? false }
        set { defaults.set(newValue, forKey: BarShelfDefaults.Key.setupCompleted) }
    }

    func mode(for item: ManagedMenuBarItem) -> VisibilityMode {
        store.mode(for: item.id)
    }

    func setMode(_ mode: VisibilityMode, for item: ManagedMenuBarItem) {
        store.setMode(mode, for: item.id)
    }

    func moveItem(_ item: ManagedMenuBarItem, to mode: VisibilityMode, before targetId: String?, among items: [ManagedMenuBarItem]) {
        let oldMode = self.mode(for: item)
        if oldMode != mode { store.setMode(mode, for: item.id) }

        if oldMode != mode {
            let oldIds = store.order(for: oldMode).filter { $0 != item.id }
            store.setOrder(oldIds, for: oldMode)
        }

        let modeIds = items.filter { self.mode(for: $0) == mode }.map(\.id)
        let persisted = store.order(for: mode).filter { modeIds.contains($0) && $0 != item.id }
        let missing = modeIds.filter { $0 != item.id && !persisted.contains($0) }
        let ordered = MenuBarItemOrdering.orderedIds(afterMoving: item.id, before: targetId, in: persisted + missing)
        store.setOrder(ordered, for: mode)
    }

    func saveLastSeenItems(_ items: [ManagedMenuBarItem]) {
        store.lastSeenItems = items.map { item in
            MenuBarItemSnapshot(id: item.id, owner: item.owner, name: item.name, x: Int(item.bounds.minX.rounded()))
        }
    }
}



final class LaunchAtLoginController {
    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        }
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

    static func openAccessibilitySettings() {
        openSettings(url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
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

    static func openScreenCaptureSettings() {
        openSettings(url: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private static func openSettings(url: String) {
        guard let url = URL(string: url) else { return }
        NSWorkspace.shared.open(url)
    }
}

final class MenuBarItemScanner {
    private let ignoredOwners = ["BarShelf", "Window Server"]
    private let ignoredBundleIdentifiers = [Bundle.main.bundleIdentifier].compactMap { $0 }
    private let axScanner = AXMenuBarItemScanner()

    func scan() -> [ManagedMenuBarItem] {
        let cgItems = scanWindowServerItems()
        let axItems = axScanner.scan()
            .filter { !ignoredOwners.contains($0.owner) }
            .filter { item in
                guard let bundleIdentifier = item.bundleIdentifier else { return true }
                return !ignoredBundleIdentifiers.contains(bundleIdentifier)
            }
        return merge(cgItems: cgItems, axItems: axItems)
            .map { item in
                guard item.image == nil,
                      let symbolName = AppleMenuExtraNameMapper.symbolName(for: item.name) else { return item }
                return item.withImage(NSImage(systemSymbolName: symbolName, accessibilityDescription: item.name))
            }
            .sorted { lhs, rhs in
                if abs(lhs.bounds.minY - rhs.bounds.minY) < 1 { return lhs.bounds.minX < rhs.bounds.minX }
                return lhs.bounds.minY < rhs.bounds.minY
            }
    }

    private func scanWindowServerItems() -> [ManagedMenuBarItem] {
        let onScreen = windowInfo(options: [.optionOnScreenOnly, .excludeDesktopElements])
        let allWindows = windowInfo(options: [.optionAll, .excludeDesktopElements])

        // Ice relies on the window server's status-window level instead of trying to infer
        // app-specific status items. Mirroring that approach catches more current macOS menu
        // extras, while the on-screen pass keeps the list tied to what the user can manage now.
        let combined = onScreen + allWindows
        var seen = Set<CGWindowID>()
        return combined.compactMap(item(from:))
            .filter { seen.insert($0.windowNumber).inserted }
            .filter { !ignoredOwners.contains($0.owner) }
            .filter { item in
                guard let bundleIdentifier = item.bundleIdentifier else { return true }
                return !ignoredBundleIdentifiers.contains(bundleIdentifier)
            }
    }

    private func merge(cgItems: [ManagedMenuBarItem], axItems: [ManagedMenuBarItem]) -> [ManagedMenuBarItem] {
        var merged = cgItems
        for axItem in axItems {
            if let index = merged.firstIndex(where: { isDuplicate($0, axItem) }) {
                if merged[index].name.isEmpty, !axItem.name.isEmpty {
                    merged[index] = merged[index].withName(axItem.name)
                }
            } else {
                merged.append(axItem)
            }
        }
        return merged
    }

    private func isDuplicate(_ lhs: ManagedMenuBarItem, _ rhs: ManagedMenuBarItem) -> Bool {
        let sameOwner = lhs.ownerPID == rhs.ownerPID || lhs.bundleIdentifier == rhs.bundleIdentifier
        guard sameOwner else { return false }
        let xClose = abs(lhs.bounds.midX - rhs.bounds.midX) <= max(8, min(lhs.bounds.width, rhs.bounds.width) / 2)
        let widthClose = abs(lhs.bounds.width - rhs.bounds.width) <= max(10, min(lhs.bounds.width, rhs.bounds.width))
        return xClose && widthClose
    }

    private func windowInfo(options: CGWindowListOption) -> [[String: Any]] {
        CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
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

        let alpha = Self.number(info[kCGWindowAlpha as String])
        let name = info[kCGWindowName as String] as? String ?? ""
        let candidate = MenuBarItemCandidate(
            layer: layer,
            x: Double(bounds.minX),
            y: Double(bounds.minY),
            width: Double(bounds.width),
            height: Double(bounds.height),
            alpha: Double(alpha),
            owner: owner,
            title: name
        )
        guard MenuBarItemCandidateFilter.accepts(candidate) else { return nil }

        let id = MenuBarItemIdentity(owner: owner, name: name, roundedX: Int(bounds.minX.rounded())).id
        let image = capture(windowNumber: CGWindowID(windowNumber), bounds: bounds)
        let ownerPID = pid_t(Int(Self.number(info[kCGWindowOwnerPID as String])))
        let bundleIdentifier = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier

        return ManagedMenuBarItem(
            id: id,
            owner: owner,
            name: name,
            ownerPID: ownerPID,
            bundleIdentifier: bundleIdentifier,
            windowNumber: CGWindowID(windowNumber),
            bounds: bounds,
            image: image
        )
    }

    private static func number(_ value: Any?) -> CGFloat {
        if let value = value as? CGFloat { return value }
        if let value = value as? Double { return CGFloat(value) }
        if let value = value as? Int { return CGFloat(value) }
        if let value = value as? NSNumber { return CGFloat(truncating: value) }
        return 0
    }

    private func capture(windowNumber: CGWindowID, bounds: CGRect) -> NSImage? {
        guard PermissionManager.hasScreenCaptureAccess else { return nil }
        guard let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowNumber, [.boundsIgnoreFraming, .nominalResolution]) else { return nil }
        return NSImage(cgImage: cgImage, size: bounds.size)
    }
}

final class AXMenuBarItemScanner {
    private let appleMenuBarOwners: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.systemuiserver"
    ]

    func scan() -> [ManagedMenuBarItem] {
        guard PermissionManager.isAccessibilityTrusted else { return [] }

        return NSWorkspace.shared.runningApplications.flatMap { app -> [ManagedMenuBarItem] in
            guard app.processIdentifier > 0 else { return [] }
            guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return [] }
            guard app.activationPolicy == .regular || app.activationPolicy == .accessory || app.activationPolicy == .prohibited else { return [] }
            return scan(app: app)
        }
    }

    private func scan(app: NSRunningApplication) -> [ManagedMenuBarItem] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let roots = menuBarRoots(for: appElement, bundleIdentifier: app.bundleIdentifier)
        guard !roots.isEmpty else { return [] }

        let owner = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        return roots.flatMap(collectMenuBarItems(from:)).compactMap { item in
            managedItem(from: item, app: app, owner: owner)
        }
    }

    private func menuBarRoots(for appElement: AXUIElement, bundleIdentifier: String?) -> [AXUIElement] {
        var roots: [AXUIElement] = []

        if let extrasBar = axElementAttribute(appElement, name: "AXExtrasMenuBar") {
            roots.append(extrasBar)
        }

        let allowMenuBarFallback = bundleIdentifier.map { appleMenuBarOwners.contains($0) } ?? false
        if roots.isEmpty, allowMenuBarFallback,
           let menuBar = axElementAttribute(appElement, name: kAXMenuBarAttribute as String) {
            roots.append(menuBar)
        }

        return roots
    }

    private func collectMenuBarItems(from root: AXUIElement) -> [AXUIElement] {
        var collected: [AXUIElement] = []

        func visit(_ node: AXUIElement) {
            let role = stringAttribute(node, name: kAXRoleAttribute as String)
            if role == (kAXMenuBarItemRole as String) || role == "AXMenuBarItem" {
                collected.append(node)
                return
            }

            guard let children = arrayAttribute(node, name: kAXChildrenAttribute as String) else { return }
            for child in children { visit(child) }
        }

        visit(root)
        return collected
    }

    private func managedItem(from element: AXUIElement, app: NSRunningApplication, owner: String) -> ManagedMenuBarItem? {
        guard let position = pointAttribute(element, name: kAXPositionAttribute as String),
              let size = sizeAttribute(element, name: kAXSizeAttribute as String) else { return nil }

        let bounds = CGRect(origin: position, size: size)
        guard AXMenuBarItemCandidateFilter.accepts(x: Double(bounds.minX), y: Double(bounds.minY), width: Double(bounds.width), height: Double(bounds.height)) else {
            return nil
        }

        let rawName = bestName(for: element, bundleIdentifier: app.bundleIdentifier, width: bounds.width)
        let name = rawName.isEmpty ? "AXMenuExtra" : rawName
        let id = MenuBarItemIdentity(owner: owner, name: name, roundedX: Int(bounds.minX.rounded())).id

        return ManagedMenuBarItem(
            id: id,
            owner: owner,
            name: name,
            ownerPID: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            windowNumber: 0,
            bounds: bounds,
            image: nil
        )
    }

    private func bestName(for element: AXUIElement, bundleIdentifier: String?, width: CGFloat) -> String {
        let identifier = stringAttribute(element, name: "AXIdentifier")
        let description = stringAttribute(element, name: kAXDescriptionAttribute as String)
        let title = stringAttribute(element, name: kAXTitleAttribute as String)
        let label = [description, title, identifier]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""

        guard let bundleIdentifier, bundleIdentifier.hasPrefix("com.apple.") else { return label }
        if let mapped = AppleMenuExtraNameMapper.displayName(for: identifier ?? label) { return mapped }
        if let mapped = AppleMenuExtraNameMapper.displayName(for: label) { return mapped }
        return label
    }

    private func axElementAttribute(_ element: AXUIElement, name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func stringAttribute(_ element: AXUIElement, name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func arrayAttribute(_ element: AXUIElement, name: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }

    private func pointAttribute(_ element: AXUIElement, name: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeAttribute(_ element: AXUIElement, name: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
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

    func update(items: [ManagedMenuBarItem], preferences: Preferences, anchorWindowFrame: NSRect?) {
        let shelfItems = orderedFloatingItems(from: items, preferences: preferences)
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
            if let image = item.image?.copy() as? NSImage {
                image.size = NSSize(width: min(max(item.bounds.width, 18), 28), height: min(max(item.bounds.height, 18), 24))
                button.image = image
            } else if let symbolName = AppleMenuExtraNameMapper.symbolName(for: item.name) ?? AppleMenuExtraNameMapper.symbolName(for: item.displayName),
                      let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: item.displayName) {
                image.isTemplate = true
                image.size = NSSize(width: 22, height: 22)
                button.image = image
            } else {
                button.title = String(item.owner.prefix(1)).uppercased()
                button.font = .systemFont(ofSize: 13, weight: .semibold)
            }
            stack.addArrangedSubview(button)
        }

        let layout = frame(itemCount: shelfItems.count, anchorWindowFrame: anchorWindowFrame)
        let width = CGFloat(layout.width)
        let height = CGFloat(layout.height)
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
        panel.setFrame(layout, display: true)
        panel.orderFrontRegardless()
    }

    private func orderedFloatingItems(from items: [ManagedMenuBarItem], preferences: Preferences) -> [ManagedMenuBarItem] {
        let shelfItems = items.filter { preferences.mode(for: $0) == .floatingShelf }
        let order = preferences.order(for: .floatingShelf)
        let orderIndex = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return shelfItems.sorted { lhs, rhs in
            let left = orderIndex[lhs.id] ?? Int.max
            let right = orderIndex[rhs.id] ?? Int.max
            if left != right { return left < right }
            return lhs.bounds.minX < rhs.bounds.minX
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 120, height: 48), styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace, .ignoresCycle]
        panel.title = "BarShelf Floating Shelf"
        panel.titlebarAppearsTransparent = true
        panel.allowsToolTipsWhenApplicationIsInactive = true
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        return panel
    }

    private func frame(itemCount: Int, anchorWindowFrame: NSRect?) -> NSRect {
        let screen = screen(containing: anchorWindowFrame) ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: screenFrame.height - 24)
        let layout = FloatingShelfLayoutCalculator.frame(
            itemCount: itemCount,
            screenMinX: Double(screenFrame.minX),
            screenMaxX: Double(screenFrame.maxX),
            visibleFrameMaxY: Double(visibleFrame.maxY),
            anchorMidX: anchorWindowFrame.map { Double($0.midX) }
        )
        return NSRect(x: CGFloat(layout.x), y: CGFloat(layout.y), width: CGFloat(layout.width), height: CGFloat(layout.height))
    }

    private func screen(containing frame: NSRect?) -> NSScreen? {
        guard let frame else { return NSScreen.main }
        return NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
    }
}


struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

final class UpdateManager {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/LVTD-LLC/barshelf/releases/latest")!
    static let releasesPageURL = URL(string: "https://github.com/LVTD-LLC/barshelf/releases/latest")!

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func fetchLatestRelease(completion: @escaping (Result<GitHubRelease, Error>) -> Void) {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("BarShelf", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data else {
                completion(.failure(NSError(domain: "BarShelfUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: "GitHub did not return release data."])))
                return
            }
            do {
                completion(.success(try JSONDecoder().decode(GitHubRelease.self, from: data)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func isNewer(latestTag: String) -> Bool {
        compareVersions(latestTag.normalizedVersion, currentVersion.normalizedVersion) == .orderedDescending
    }

    func updateWithHomebrew(completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", "export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; if ! command -v brew >/dev/null 2>&1; then exit 42; fi; if ! brew list --cask barshelf >/dev/null 2>&1; then exit 43; fi; brew update && brew upgrade --cask barshelf"]

            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("barshelf-homebrew-update-\(UUID().uuidString).log")
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)

            do {
                let outputHandle = try FileHandle(forWritingTo: outputURL)
                defer {
                    try? outputHandle.close()
                    try? FileManager.default.removeItem(at: outputURL)
                }
                process.standardOutput = outputHandle
                process.standardError = outputHandle

                try process.run()
                process.waitUntilExit()
                let data = (try? Data(contentsOf: outputURL)) ?? Data()
                let output = String(data: data, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    completion(.success(output))
                } else {
                    let message: String
                    switch process.terminationStatus {
                    case 42:
                        message = "Homebrew was not found on this Mac."
                    case 43:
                        message = "BarShelf does not appear to be installed through Homebrew."
                    default:
                        message = output.isEmpty ? "Homebrew exited with status \(process.terminationStatus)." : output
                    }
                    completion(.failure(NSError(domain: "BarShelfUpdate", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l > r { return .orderedDescending }
            if l < r { return .orderedAscending }
        }
        return .orderedSame
    }
}

private extension String {
    var normalizedVersion: String {
        trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }
}

private enum SettingsDragPasteboard {
    static let type = NSPasteboard.PasteboardType("com.gregagi.barshelf.menu-item-id")
}

final class IconTileButton: NSButton {
    let itemId: String

    init(itemId: String) {
        self.itemId = itemId
        super.init(frame: .zero)
        registerForDraggedTypes([SettingsDragPasteboard.type])
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDragged(with event: NSEvent) {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(itemId, forType: SettingsDragPasteboard.type)
        let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
        item.setDraggingFrame(bounds, contents: draggingImage())
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .move }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .move }

    private func draggingImage() -> NSImage {
        let representation = bitmapImageRepForCachingDisplay(in: bounds)
        let image = NSImage(size: bounds.size)
        if let representation {
            cacheDisplay(in: bounds, to: representation)
            image.addRepresentation(representation)
        }
        return image
    }
}

extension IconTileButton: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}

final class ModeDropRowView: NSView {
    let mode: VisibilityMode
    var onDropItem: ((String, VisibilityMode, String?) -> Void)?
    private var targeted = false { didSet { needsDisplay = true } }

    init(mode: VisibilityMode) {
        self.mode = mode
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.7).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        registerForDraggedTypes([SettingsDragPasteboard.type])
    }

    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        targeted = true
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 2
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .move }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        targeted = false
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        layer?.borderWidth = 1
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { draggingExited(nil) }
        guard let id = sender.draggingPasteboard.string(forType: SettingsDragPasteboard.type) else { return false }
        onDropItem?(id, mode, targetId(at: convert(sender.draggingLocation, from: nil)))
        return true
    }

    private func targetId(at point: NSPoint) -> String? {
        func collectButtons(in view: NSView) -> [IconTileButton] {
            let direct = (view as? IconTileButton).map { [$0] } ?? []
            return direct + view.subviews.flatMap(collectButtons(in:))
        }
        let candidates = collectButtons(in: self)
        return candidates
            .map { button -> (String, CGFloat) in
                let frame = convert(button.bounds, from: button)
                return (button.itemId, abs(point.x - frame.midX))
            }
            .sorted { $0.1 < $1.1 }
            .first?.0
    }
}

final class BarShelfController: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private let scanner = MenuBarItemScanner()
    private let launchAtLogin = LaunchAtLoginController()
    private let updateManager = UpdateManager()
    private let overlays = MaskOverlayController()
    private var floatingShelf: FloatingShelfWindowController!
    private var managedItems: [ManagedMenuBarItem] = []

    private var toggleItem: NSStatusItem!
    private var separatorItem: NSStatusItem!
    private var shelfSpacerItem: NSStatusItem!
    private var alwaysHiddenSeparatorItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var setupAccessibilityValue: NSTextField?
    private var setupScreenCaptureValue: NSTextField?
    private var setupFinishButton: NSButton?
    private var setupLaunchAtLoginCheckbox: NSButton?
    private var setupTimer: Timer?
    private var settingsShortcutMonitor: Any?
    private var scanTimer: Timer?
    private var collapseTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        floatingShelf = FloatingShelfWindowController(controller: self)
        createAppMenu()
        createStatusItems()
        registerSettingsShortcut()
        registerCLICommandListener()
        applyLegacyState(animated: false)
        rescanAndApply()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.rescanAndApply()
        }
        showSetupIfNeeded()
    }

    private func createAppMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "BarShelf")

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem(title: "Setup", action: #selector(openSetup), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: ""))
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit BarShelf", action: #selector(quit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        appMenu.addItem(quitItem)
        appMenu.items.forEach { $0.target = self }

        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
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
        configureButton(toggleItem.button, title: "", help: "Show BarShelf hidden icons")
        if let image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "BarShelf") ?? NSImage(systemSymbolName: "rectangle.grid.2x2", accessibilityDescription: "BarShelf") {
            image.isTemplate = true
            toggleItem.button?.image = image
            toggleItem.button?.imagePosition = .imageOnly
        } else {
            toggleItem.button?.title = "▦"
        }
        toggleItem.button?.target = self
        toggleItem.button?.action = #selector(toggleShelf)
        toggleItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        statusMenu = NSMenu()
        statusMenu.addItem(NSMenuItem(title: "Show / hide hidden icons", action: #selector(toggleShelfFromMenu), keyEquivalent: ""))
        statusMenu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        statusMenu.addItem(NSMenuItem(title: "Setup", action: #selector(openSetup), keyEquivalent: ""))
        statusMenu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: ""))
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

    private func registerSettingsShortcut() {
        settingsShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
                  event.charactersIgnoringModifiers == "," else { return event }
            self?.openSettings()
            return nil
        }
    }


    @objc private func toggleShelf() {
        if NSApp.currentEvent?.type == .rightMouseUp, let button = toggleItem.button {
            statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
            return
        }
        preferences.shelfVisible.toggle()
        rescanAndApply()
    }

    @objc private func toggleShelfFromMenu() {
        preferences.shelfVisible.toggle()
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
        preferences.saveLastSeenItems(managedItems)
        guard preferences.useAdvancedRouting else {
            floatingShelf.hide()
            return
        }
        overlays.apply(items: managedItems, preferences: preferences)
        if preferences.shelfVisible {
            floatingShelf.update(items: managedItems, preferences: preferences, anchorWindowFrame: toggleItem.button?.window?.frame)
            toggleItem.button?.title = "▦"
            toggleItem.button?.toolTip = "Hide BarShelf hidden icons"
        } else {
            floatingShelf.hide()
            toggleItem.button?.title = "▦"
            toggleItem.button?.toolTip = "Show BarShelf hidden icons"
        }
    }

    private func registerCLICommandListener() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleCLICommand(_:)),
            name: BarShelfIPC.notificationName,
            object: nil
        )
    }

    @objc private func handleCLICommand(_ notification: Notification) {
        guard let raw = notification.userInfo?["command"] as? String,
              let command = BarShelfIPC.Command(rawValue: raw) else { return }

        switch command {
        case .show:
            preferences.shelfVisible = true
            rescanAndApply()
        case .hide:
            preferences.shelfVisible = false
            rescanAndApply()
        case .toggle:
            preferences.shelfVisible.toggle()
            rescanAndApply()
        case .rescan:
            rescanAndApply()
            rebuildSettingsWindowIfOpen()
        case .openSettings:
            openSettings()
        case .permissions:
            requestPermissions()
        case .launchAtLoginOn:
            setLaunchAtLogin(true)
        case .launchAtLoginOff:
            setLaunchAtLogin(false)
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

    private func showSetupIfNeeded() {
        guard !preferences.setupCompleted || !PermissionManager.isAccessibilityTrusted else { return }
        openSetup()
    }

    @objc private func openSetup() {
        buildSetupWindow()
        setupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startSetupStatusUpdates()
    }

    private func buildSetupWindow() {
        if setupWindow != nil {
            updateSetupStatus()
            return
        }

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 430))

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown

        let title = NSTextField(labelWithString: "Set up BarShelf")
        title.font = .systemFont(ofSize: 28, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let intro = NSTextField(wrappingLabelWithString: "BarShelf runs from the macOS menu bar. Before it can manage hidden menu bar icons, enable Accessibility permission. Screen Recording is recommended so BarShelf can show real icon previews in the floating shelf.")
        intro.textColor = .secondaryLabelColor
        intro.translatesAutoresizingMaskIntoConstraints = false

        let accessibilityTitle = NSTextField(labelWithString: "Accessibility")
        accessibilityTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        accessibilityTitle.translatesAutoresizingMaskIntoConstraints = false

        let accessibilityValue = NSTextField(labelWithString: "")
        accessibilityValue.translatesAutoresizingMaskIntoConstraints = false
        setupAccessibilityValue = accessibilityValue

        let accessibilityButton = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openAccessibilitySettingsFromSetup))
        accessibilityButton.translatesAutoresizingMaskIntoConstraints = false

        let screenTitle = NSTextField(labelWithString: "Screen Recording")
        screenTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        screenTitle.translatesAutoresizingMaskIntoConstraints = false

        let screenValue = NSTextField(labelWithString: "")
        screenValue.translatesAutoresizingMaskIntoConstraints = false
        setupScreenCaptureValue = screenValue

        let screenButton = NSButton(title: "Open Screen Recording Settings", target: self, action: #selector(openScreenCaptureSettingsFromSetup))
        screenButton.translatesAutoresizingMaskIntoConstraints = false

        let launchCheckbox = NSButton(checkboxWithTitle: "Launch BarShelf at login", target: self, action: #selector(setupLaunchAtLoginChanged(_:)))
        launchCheckbox.state = launchAtLogin.isEnabled ? .on : .off
        launchCheckbox.translatesAutoresizingMaskIntoConstraints = false
        setupLaunchAtLoginCheckbox = launchCheckbox

        let note = NSTextField(wrappingLabelWithString: "After enabling Accessibility, return here. The Finish Setup button will unlock automatically.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 12)
        note.translatesAutoresizingMaskIntoConstraints = false

        let finishButton = NSButton(title: "Finish Setup", target: self, action: #selector(finishSetup))
        finishButton.keyEquivalent = "\r"
        finishButton.translatesAutoresizingMaskIntoConstraints = false
        setupFinishButton = finishButton

        let quitButton = NSButton(title: "Quit", target: self, action: #selector(quit))
        quitButton.translatesAutoresizingMaskIntoConstraints = false

        [iconView, title, intro, accessibilityTitle, accessibilityValue, accessibilityButton, screenTitle, screenValue, screenButton, launchCheckbox, note, finishButton, quitButton].forEach(content.addSubview)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),
            iconView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 30),
            title.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),

            intro.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            intro.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            intro.trailingAnchor.constraint(equalTo: title.trailingAnchor),

            accessibilityTitle.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 28),
            accessibilityTitle.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            accessibilityValue.centerYAnchor.constraint(equalTo: accessibilityTitle.centerYAnchor),
            accessibilityValue.leadingAnchor.constraint(equalTo: accessibilityTitle.trailingAnchor, constant: 12),
            accessibilityButton.topAnchor.constraint(equalTo: accessibilityTitle.bottomAnchor, constant: 8),
            accessibilityButton.leadingAnchor.constraint(equalTo: accessibilityTitle.leadingAnchor),

            screenTitle.topAnchor.constraint(equalTo: accessibilityButton.bottomAnchor, constant: 22),
            screenTitle.leadingAnchor.constraint(equalTo: accessibilityTitle.leadingAnchor),
            screenValue.centerYAnchor.constraint(equalTo: screenTitle.centerYAnchor),
            screenValue.leadingAnchor.constraint(equalTo: screenTitle.trailingAnchor, constant: 12),
            screenButton.topAnchor.constraint(equalTo: screenTitle.bottomAnchor, constant: 8),
            screenButton.leadingAnchor.constraint(equalTo: screenTitle.leadingAnchor),

            launchCheckbox.topAnchor.constraint(equalTo: screenButton.bottomAnchor, constant: 24),
            launchCheckbox.leadingAnchor.constraint(equalTo: accessibilityTitle.leadingAnchor),

            note.topAnchor.constraint(equalTo: launchCheckbox.bottomAnchor, constant: 14),
            note.leadingAnchor.constraint(equalTo: accessibilityTitle.leadingAnchor),
            note.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),

            finishButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            finishButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            quitButton.trailingAnchor.constraint(equalTo: finishButton.leadingAnchor, constant: -10),
            quitButton.centerYAnchor.constraint(equalTo: finishButton.centerYAnchor)
        ])

        let window = NSWindow(contentRect: content.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Set up BarShelf"
        window.isReleasedWhenClosed = false
        window.contentView = content
        window.center()
        setupWindow = window
        updateSetupStatus()
    }

    private func startSetupStatusUpdates() {
        setupTimer?.invalidate()
        setupTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateSetupStatus()
        }
    }

    private func updateSetupStatus() {
        let accessibilityEnabled = PermissionManager.isAccessibilityTrusted
        let screenCaptureEnabled = PermissionManager.hasScreenCaptureAccess

        setupAccessibilityValue?.stringValue = accessibilityEnabled ? "Enabled" : "Not enabled"
        setupAccessibilityValue?.textColor = accessibilityEnabled ? .systemGreen : .systemRed
        setupScreenCaptureValue?.stringValue = screenCaptureEnabled ? "Enabled" : "Not enabled"
        setupScreenCaptureValue?.textColor = screenCaptureEnabled ? .systemGreen : .systemOrange
        setupLaunchAtLoginCheckbox?.state = launchAtLogin.isEnabled ? .on : .off
        setupFinishButton?.isEnabled = accessibilityEnabled
    }

    @objc private func openAccessibilitySettingsFromSetup() {
        PermissionManager.requestAccessibility()
        PermissionManager.openAccessibilitySettings()
        updateSetupStatus()
    }

    @objc private func openScreenCaptureSettingsFromSetup() {
        PermissionManager.requestScreenCapture()
        PermissionManager.openScreenCaptureSettings()
        updateSetupStatus()
    }

    @objc private func setupLaunchAtLoginChanged(_ sender: NSButton) {
        setLaunchAtLogin(sender.state == .on)
        updateSetupStatus()
    }

    @objc private func finishSetup() {
        guard PermissionManager.isAccessibilityTrusted else {
            updateSetupStatus()
            return
        }
        preferences.setupCompleted = true
        setupTimer?.invalidate()
        setupWindow?.close()
        setupWindow = nil
        rescanAndApply()
        openSettings()
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

        let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch BarShelf at login", target: self, action: #selector(launchAtLoginChanged(_:)))
        launchAtLoginCheckbox.state = launchAtLogin.isEnabled ? .on : .off
        launchAtLoginCheckbox.translatesAutoresizingMaskIntoConstraints = false

        let permissionButton = NSButton(title: "Request permissions", target: self, action: #selector(requestPermissions))
        permissionButton.translatesAutoresizingMaskIntoConstraints = false

        let updateButton = NSButton(title: "Check for Updates", target: self, action: #selector(checkForUpdates))
        updateButton.translatesAutoresizingMaskIntoConstraints = false

        let rescanButton = NSButton(title: "Rescan", target: self, action: #selector(rescanFromSettings))
        rescanButton.translatesAutoresizingMaskIntoConstraints = false

        let organizer = settingsOrganizerView()
        organizer.translatesAutoresizingMaskIntoConstraints = false

        let organizerHelp = NSTextField(labelWithString: "Drag icons between rows to change state. Drag within a row to set BarShelf's preferred order.")
        organizerHelp.textColor = .secondaryLabelColor
        organizerHelp.font = .systemFont(ofSize: 12)
        organizerHelp.translatesAutoresizingMaskIntoConstraints = false

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

        [title, instructions, advanced, launchAtLoginCheckbox, permissionButton, updateButton, rescanButton, organizer, organizerHelp, legacyTitle, widthLabel, widthSlider, alwaysHidden].forEach(content.addSubview)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            instructions.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            instructions.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            instructions.trailingAnchor.constraint(equalTo: title.trailingAnchor),

            advanced.topAnchor.constraint(equalTo: instructions.bottomAnchor, constant: 18),
            advanced.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            launchAtLoginCheckbox.topAnchor.constraint(equalTo: advanced.bottomAnchor, constant: 12),
            launchAtLoginCheckbox.leadingAnchor.constraint(equalTo: title.leadingAnchor),

            permissionButton.centerYAnchor.constraint(equalTo: launchAtLoginCheckbox.centerYAnchor),
            permissionButton.leadingAnchor.constraint(equalTo: launchAtLoginCheckbox.trailingAnchor, constant: 18),
            updateButton.centerYAnchor.constraint(equalTo: launchAtLoginCheckbox.centerYAnchor),
            updateButton.leadingAnchor.constraint(equalTo: permissionButton.trailingAnchor, constant: 10),
            rescanButton.centerYAnchor.constraint(equalTo: launchAtLoginCheckbox.centerYAnchor),
            rescanButton.leadingAnchor.constraint(equalTo: updateButton.trailingAnchor, constant: 10),

            organizer.topAnchor.constraint(equalTo: launchAtLoginCheckbox.bottomAnchor, constant: 18),
            organizer.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            organizer.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            organizer.heightAnchor.constraint(equalToConstant: 246),

            organizerHelp.topAnchor.constraint(equalTo: organizer.bottomAnchor, constant: 8),
            organizerHelp.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            organizerHelp.trailingAnchor.constraint(equalTo: title.trailingAnchor),

            legacyTitle.topAnchor.constraint(equalTo: organizerHelp.bottomAnchor, constant: 20),
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

    private func settingsOrganizerView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.distribution = .fillEqually
        stack.spacing = 8

        if managedItems.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: "No menu bar items detected yet. Grant Accessibility and Screen Recording permissions, then click Rescan.")
            empty.textColor = .secondaryLabelColor
            empty.alignment = .center
            stack.addArrangedSubview(empty)
            return stack
        }

        for mode in VisibilityMode.allCases {
            stack.addArrangedSubview(settingsRow(for: mode))
        }

        return stack
    }

    private func settingsRow(for mode: VisibilityMode) -> NSView {
        let row = ModeDropRowView(mode: mode)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.onDropItem = { [weak self] itemId, mode, targetId in
            self?.moveSettingsItem(id: itemId, to: mode, before: targetId)
        }

        let label = NSTextField(labelWithString: mode.label)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = iconBorderColor(for: mode)
        label.translatesAutoresizingMaskIntoConstraints = false

        let count = NSTextField(labelWithString: "\(orderedItems(for: mode).count)")
        count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        count.textColor = .secondaryLabelColor
        count.translatesAutoresizingMaskIntoConstraints = false

        let iconStack = NSStackView()
        iconStack.orientation = .horizontal
        iconStack.alignment = .centerY
        iconStack.spacing = 6
        iconStack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        iconStack.translatesAutoresizingMaskIntoConstraints = false

        let items = orderedItems(for: mode)
        if items.isEmpty {
            let empty = NSTextField(labelWithString: "Drop icons here")
            empty.textColor = .tertiaryLabelColor
            empty.font = .systemFont(ofSize: 12)
            iconStack.addArrangedSubview(empty)
        } else {
            items.forEach { iconStack.addArrangedSubview(iconCard(for: $0)) }
        }

        let scroll = NSScrollView()
        scroll.documentView = iconStack
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(label)
        row.addSubview(count)
        row.addSubview(scroll)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 118),

            count.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            count.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            count.widthAnchor.constraint(equalToConstant: 26),

            scroll.leadingAnchor.constraint(equalTo: count.trailingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: row.topAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -6),

            iconStack.heightAnchor.constraint(equalTo: scroll.contentView.heightAnchor),
            iconStack.widthAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.widthAnchor)
        ])

        return row
    }

    private func orderedItems(for mode: VisibilityMode) -> [ManagedMenuBarItem] {
        let items = managedItems.filter { preferences.mode(for: $0) == mode }
        let order = preferences.order(for: mode)
        let orderIndex = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return items.sorted { lhs, rhs in
            let left = orderIndex[lhs.id] ?? Int.max
            let right = orderIndex[rhs.id] ?? Int.max
            if left != right { return left < right }
            return lhs.bounds.minX < rhs.bounds.minX
        }
    }

    private func iconCard(for item: ManagedMenuBarItem) -> NSView {
        let mode = preferences.mode(for: item)
        let button = IconTileButton(itemId: item.id)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.toolTip = "\(item.displayName) — \(mode.label). Drag to move or reorder."
        button.target = nil
        button.action = nil
        button.identifier = NSUserInterfaceItemIdentifier(item.id)
        button.setButtonType(.momentaryChange)
        button.wantsLayer = true
        button.layer?.cornerRadius = 10
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = iconBackgroundColor(for: mode).cgColor
        button.layer?.borderWidth = 2
        button.layer?.borderColor = iconBorderColor(for: mode).cgColor

        if let image = renderedIconImage(for: item) {
            button.image = image
            button.imagePosition = .imageOnly
            if image.isTemplate { button.contentTintColor = .white }
        } else {
            let title = String(item.displayName.prefix(1)).uppercased()
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.systemFont(ofSize: 14, weight: .semibold)
                ]
            )
            button.font = .systemFont(ofSize: 14, weight: .semibold)
            button.imagePosition = .noImage
        }

        button.widthAnchor.constraint(equalToConstant: 46).isActive = true
        button.heightAnchor.constraint(equalToConstant: 38).isActive = true
        return button
    }

    private func renderedIconImage(for item: ManagedMenuBarItem) -> NSImage? {
        if let image = item.image?.copy() as? NSImage {
            image.size = NSSize(width: min(max(item.bounds.width, 18), 28), height: min(max(item.bounds.height, 18), 24))
            return image
        }
        if let symbolName = AppleMenuExtraNameMapper.symbolName(for: item.name) ?? AppleMenuExtraNameMapper.symbolName(for: item.displayName) {
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: item.displayName)
            image?.isTemplate = true
            image?.size = NSSize(width: 22, height: 22)
            return image
        }
        return nil
    }

    private func moveSettingsItem(id: String, to mode: VisibilityMode, before targetId: String?) {
        guard let item = managedItems.first(where: { $0.id == id }) else { return }
        preferences.moveItem(item, to: mode, before: targetId == id ? nil : targetId, among: managedItems)
        rescanAndApply()
        rebuildSettingsWindowIfOpen()
    }

    private func iconBackgroundColor(for mode: VisibilityMode) -> NSColor {
        switch mode {
        case .alwaysShown: return NSColor.black.withAlphaComponent(0.72)
        case .floatingShelf: return NSColor.systemBlue.withAlphaComponent(0.24)
        case .alwaysHidden: return NSColor.systemGray.withAlphaComponent(0.28)
        }
    }

    private func iconBorderColor(for mode: VisibilityMode) -> NSColor {
        switch mode {
        case .alwaysShown: return NSColor.separatorColor.withAlphaComponent(0.75)
        case .floatingShelf: return .systemBlue
        case .alwaysHidden: return .systemGray
        }
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

    @objc private func iconModeClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let item = managedItems.first(where: { $0.id == id }) else { return }
        preferences.setMode(nextMode(after: preferences.mode(for: item)), for: item)
        rescanAndApply()
        rebuildSettingsWindowIfOpen()
    }

    private func nextMode(after mode: VisibilityMode) -> VisibilityMode {
        switch mode {
        case .alwaysShown: return .floatingShelf
        case .floatingShelf: return .alwaysHidden
        case .alwaysHidden: return .alwaysShown
        }
    }

    @objc private func advancedRoutingChanged(_ sender: NSButton) {
        preferences.useAdvancedRouting = sender.state == .on
        rescanAndApply()
    }

    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        setLaunchAtLogin(sender.state == .on)
        sender.state = launchAtLogin.isEnabled ? .on : .off
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not update Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @objc private func rescanFromSettings() {
        rescanAndApply()
        rebuildSettingsWindowIfOpen()
    }

    @objc private func checkForUpdates() {
        updateManager.fetchLatestRelease { [weak self] result in
            DispatchQueue.main.async {
                self?.handleUpdateCheck(result)
            }
        }
    }

    private func handleUpdateCheck(_ result: Result<GitHubRelease, Error>) {
        switch result {
        case .failure(let error):
            showUpdateError("Could not check for updates", error.localizedDescription)
        case .success(let release):
            guard updateManager.isNewer(latestTag: release.tagName) else {
                let alert = NSAlert()
                alert.messageText = "BarShelf is up to date"
                alert.informativeText = "Installed version: \(updateManager.currentVersion)\nLatest version: \(release.tagName.normalizedVersion)"
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }

            let alert = NSAlert()
            alert.messageText = "BarShelf \(release.tagName.normalizedVersion) is available"
            alert.informativeText = "Installed version: \(updateManager.currentVersion)\n\nIf BarShelf was installed with Homebrew, BarShelf can run the cask upgrade for you. Otherwise, open the latest release and install the DMG manually."
            alert.addButton(withTitle: "Update with Homebrew")
            alert.addButton(withTitle: "Open Release")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                runHomebrewUpdate()
            } else if response == .alertSecondButtonReturn {
                openLatestRelease(urlString: release.htmlURL)
            }
        }
    }

    private func runHomebrewUpdate() {
        updateManager.updateWithHomebrew { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let output):
                    let alert = NSAlert()
                    alert.messageText = "Update command completed"
                    alert.informativeText = output.isEmpty ? "Homebrew finished without output. Reopen BarShelf to use the new version." : "Homebrew finished. Reopen BarShelf to use the new version.\n\n\(output.prefix(1600))"
                    alert.addButton(withTitle: "Quit BarShelf")
                    alert.addButton(withTitle: "OK")
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSApp.terminate(nil)
                    }
                case .failure(let error):
                    self?.showUpdateError("Could not update with Homebrew", "\(error.localizedDescription)\n\nOpening the latest release page instead.")
                    NSWorkspace.shared.open(UpdateManager.releasesPageURL)
                }
            }
        }
    }

    private func openLatestRelease(urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(UpdateManager.releasesPageURL)
        }
    }

    private func showUpdateError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
