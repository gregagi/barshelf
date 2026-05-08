import Foundation

public enum VisibilityMode: String, CaseIterable, Codable, Equatable {
    case alwaysShown
    case floatingShelf
    case alwaysHidden

    public var label: String {
        switch self {
        case .alwaysShown: return "Always shown"
        case .floatingShelf: return "Floating shelf"
        case .alwaysHidden: return "Always hidden"
        }
    }

    public var cliName: String {
        switch self {
        case .alwaysShown: return "always-shown"
        case .floatingShelf: return "floating-shelf"
        case .alwaysHidden: return "always-hidden"
        }
    }

    public static func parse(_ value: String) -> VisibilityMode? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allCases.first { mode in
            mode.rawValue.lowercased() == normalized || mode.cliName == normalized
        }
    }
}

public struct MenuBarItemIdentity: Equatable {
    public let owner: String
    public let name: String
    public let roundedX: Int

    public init(owner: String, name: String, roundedX: Int) {
        self.owner = owner
        self.name = name
        self.roundedX = roundedX
    }

    public var id: String {
        let stableName = name.isEmpty ? "status-item" : name
        return "\(owner)|\(stableName)|\(roundedX)"
    }

    public var displayName: String {
        if name.isEmpty { return owner }
        return "\(owner) — \(name)"
    }
}

public struct MenuBarItemCandidate: Equatable {
    public let layer: Int
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let alpha: Double
    public let owner: String
    public let title: String

    public init(layer: Int, x: Double, y: Double, width: Double, height: Double, alpha: Double, owner: String, title: String) {
        self.layer = layer
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.alpha = alpha
        self.owner = owner
        self.title = title
    }
}

public enum MenuBarItemCandidateFilter {
    public static let statusWindowLevel = 25

    public static func accepts(_ candidate: MenuBarItemCandidate, menuBarMaxY: Double = 40) -> Bool {
        guard candidate.layer == statusWindowLevel else { return false }
        guard candidate.alpha > 0.01 else { return false }
        guard candidate.height >= 14 && candidate.height <= 44 else { return false }
        guard candidate.width >= 4 && candidate.width <= 260 else { return false }
        guard candidate.y <= menuBarMaxY else { return false }
        guard candidate.owner != "Window Server" else { return false }
        return true
    }
}

public enum AXMenuBarItemCandidateFilter {
    public static func accepts(x: Double, y: Double, width: Double, height: Double, menuBarMaxY: Double = 48) -> Bool {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite else { return false }
        guard y <= menuBarMaxY else { return false }
        guard width >= 4 && width <= 280 else { return false }
        guard height >= 12 && height <= 48 else { return false }
        return true
    }
}

public enum AppleMenuExtraNameMapper {
    public static func displayName(for raw: String) -> String? {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return nil }
        let compact = lower.replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
        let components = Set(lower.split { !$0.isLetter && !$0.isNumber }.map(String.init))

        let aliases: [String: String] = [
            "accessibilityshortcuts": "Accessibility Shortcuts",
            "airdrop": "AirDrop",
            "airplay": "AirPlay",
            "audiovideomodule": "Audio/Video",
            "battery": "Battery",
            "bluetooth": "Bluetooth",
            "bentobox": "Control Center",
            "clock": "Clock",
            "controlcenter": "Control Center",
            "display": "Display",
            "focus": "Focus",
            "focusmodes": "Focus",
            "keyboardbrightness": "Keyboard Brightness",
            "musicrecognition": "Music Recognition",
            "networkspeed": "Network Speed",
            "nowplaying": "Now Playing",
            "screenmirroring": "Screen Mirroring",
            "siri": "Siri",
            "sound": "Sound",
            "spotlight": "Spotlight",
            "stagemanager": "Stage Manager",
            "timemachine": "Time Machine",
            "userswitcher": "Fast User Switching",
            "wifi": "Wi-Fi"
        ]

        for (token, name) in aliases {
            if lower == token || compact == token || components.contains(token) || lower.contains("menuextra.\(token)") {
                return name
            }
        }
        return nil
    }

    public static func symbolName(for displayName: String) -> String? {
        switch displayName.lowercased() {
        case "accessibility shortcuts": return "accessibility"
        case "airdrop": return "airdrop"
        case "airplay": return "airplayvideo"
        case "audio/video": return "video.fill"
        case "battery": return "battery.75percent"
        case "bluetooth": return "bluetooth"
        case "control center": return "switch.2"
        case "display": return "display"
        case "focus": return "moon.fill"
        case "keyboard brightness": return "keyboard"
        case "music recognition": return "shazam.logo"
        case "network speed": return "speedometer"
        case "now playing": return "play.circle.fill"
        case "screen mirroring": return "rectangle.on.rectangle"
        case "siri": return "sparkles"
        case "sound": return "speaker.wave.2.fill"
        case "spotlight": return "magnifyingglass"
        case "stage manager": return "rectangle.3.group"
        case "time machine": return "clock.arrow.circlepath"
        case "fast user switching": return "person.crop.circle"
        case "wi-fi": return "wifi"
        default: return nil
        }
    }
}

public struct FloatingShelfLayout: Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum FloatingShelfLayoutCalculator {
    public static func frame(
        itemCount: Int,
        screenMinX: Double,
        screenMaxX: Double,
        visibleFrameMaxY: Double,
        anchorMidX: Double?,
        gapBelowMenuBar: Double = 8
    ) -> FloatingShelfLayout {
        let width = max(88, Double(itemCount) * 38 + 28)
        let height: Double = 48
        let lowerBound = screenMinX + 8
        let upperBound = screenMaxX - width - 8
        let preferredX = (anchorMidX ?? (screenMaxX - width / 2 - 18)) - width / 2
        let x: Double
        if lowerBound <= upperBound {
            x = min(max(preferredX, lowerBound), upperBound)
        } else {
            x = screenMinX
        }
        let y = visibleFrameMaxY - height - gapBelowMenuBar
        return FloatingShelfLayout(x: x, y: y, width: width, height: height)
    }
}

public struct MenuBarItemSnapshot: Codable, Equatable, Identifiable {
    public let id: String
    public let owner: String
    public let name: String
    public let x: Int

    public init(id: String, owner: String, name: String, x: Int) {
        self.id = id
        self.owner = owner
        self.name = name
        self.x = x
    }

    public var displayName: String {
        MenuBarItemIdentity(owner: owner, name: name, roundedX: x).displayName
    }
}

public enum VisibilityModeCodec {
    public static func encode(_ modes: [String: VisibilityMode]) throws -> Data {
        let raw = modes.mapValues(\.rawValue)
        return try JSONEncoder().encode(raw)
    }

    public static func decode(_ data: Data?) -> [String: VisibilityMode] {
        guard let data,
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return raw.compactMapValues(VisibilityMode.init(rawValue:))
    }
}

public enum ItemOrderCodec {
    public static func encode(_ order: [String: [String]]) throws -> Data {
        try JSONEncoder().encode(order)
    }

    public static func decode(_ data: Data?) -> [String: [String]] {
        guard let data,
              let raw = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return raw
    }
}

public enum MenuBarItemOrdering {
    public static func orderedIds(afterMoving id: String, before targetId: String?, in ids: [String]) -> [String] {
        var result = ids.filter { $0 != id }
        if let targetId, let index = result.firstIndex(of: targetId) {
            result.insert(id, at: index)
        } else {
            result.append(id)
        }
        return result
    }
}

public enum BarShelfDefaults {
    public static let suiteName = "com.gregagi.barshelf"

    public enum Key {
        public static let collapsed = "collapsed.v1"
        public static let spacerWidth = "spacerWidth.v1"
        public static let alwaysHiddenEnabled = "alwaysHiddenEnabled.v1"
        public static let autoCollapseSeconds = "autoCollapseSeconds.v1"
        public static let itemModes = "itemModes.v2"
        public static let itemOrder = "itemOrder.v1"
        public static let useAdvancedRouting = "useAdvancedRouting.v2"
        public static let shelfVisible = "shelfVisible.v1"
        public static let lastSeenItems = "lastSeenItems.v1"
        public static let lastScanAt = "lastScanAt.v1"
        public static let setupCompleted = "setupCompleted.v1"
    }

    public static func store() -> UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}

public struct BarShelfSettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = BarShelfDefaults.store()) {
        self.defaults = defaults
    }

    public var useAdvancedRouting: Bool {
        get { defaults.object(forKey: BarShelfDefaults.Key.useAdvancedRouting) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: BarShelfDefaults.Key.useAdvancedRouting) }
    }

    public var shelfVisible: Bool {
        get { defaults.object(forKey: BarShelfDefaults.Key.shelfVisible) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: BarShelfDefaults.Key.shelfVisible) }
    }

    public var itemModes: [String: VisibilityMode] {
        get { VisibilityModeCodec.decode(defaults.data(forKey: BarShelfDefaults.Key.itemModes)) }
        nonmutating set {
            if let data = try? VisibilityModeCodec.encode(newValue) {
                defaults.set(data, forKey: BarShelfDefaults.Key.itemModes)
            }
        }
    }

    public var itemOrder: [String: [String]] {
        get { ItemOrderCodec.decode(defaults.data(forKey: BarShelfDefaults.Key.itemOrder)) }
        nonmutating set {
            if let data = try? ItemOrderCodec.encode(newValue) {
                defaults.set(data, forKey: BarShelfDefaults.Key.itemOrder)
            }
        }
    }

    public var lastSeenItems: [MenuBarItemSnapshot] {
        get {
            guard let data = defaults.data(forKey: BarShelfDefaults.Key.lastSeenItems),
                  let items = try? JSONDecoder().decode([MenuBarItemSnapshot].self, from: data) else { return [] }
            return items
        }
        nonmutating set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: BarShelfDefaults.Key.lastSeenItems)
                defaults.set(Date().timeIntervalSince1970, forKey: BarShelfDefaults.Key.lastScanAt)
            }
        }
    }

    public var lastScanAt: Date? {
        let timestamp = defaults.double(forKey: BarShelfDefaults.Key.lastScanAt)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    public func mode(for itemId: String) -> VisibilityMode {
        itemModes[itemId] ?? .alwaysShown
    }

    public func setMode(_ mode: VisibilityMode, for itemId: String) {
        var modes = itemModes
        modes[itemId] = mode
        itemModes = modes
    }

    public func order(for mode: VisibilityMode) -> [String] {
        itemOrder[mode.rawValue] ?? []
    }

    public func setOrder(_ ids: [String], for mode: VisibilityMode) {
        var order = itemOrder
        order[mode.rawValue] = ids
        itemOrder = order
    }

    public func synchronize() {
        defaults.synchronize()
    }
}

public enum BarShelfIPC {
    public static let notificationName = Notification.Name("com.gregagi.barshelf.cli.command")

    public enum Command: String, CaseIterable {
        case show
        case hide
        case toggle
        case rescan
        case openSettings = "open-settings"
        case permissions
        case launchAtLoginOn = "launch-at-login-on"
        case launchAtLoginOff = "launch-at-login-off"
    }
}

public enum CLICommand: Equatable {
    case help
    case status(json: Bool)
    case list(json: Bool)
    case show
    case hide
    case toggle
    case rescan
    case openSettings
    case permissions
    case launchAtLoginStatus(json: Bool)
    case launchAtLoginEnable
    case launchAtLoginDisable
    case installCLI(path: String?, force: Bool)
    case uninstallCLI(path: String?)
    case set(itemId: String, mode: VisibilityMode)
}

public enum CLIParserError: Error, Equatable, CustomStringConvertible {
    case unknownCommand(String)
    case missingItemId
    case missingMode
    case invalidMode(String)
    case tooManyArguments([String])
    case missingPathValue

    public var description: String {
        switch self {
        case .unknownCommand(let command): return "Unknown command: \(command)"
        case .missingItemId: return "Missing item id"
        case .missingMode: return "Missing visibility mode"
        case .invalidMode(let mode): return "Invalid visibility mode: \(mode)"
        case .tooManyArguments(let args): return "Too many arguments: \(args.joined(separator: " "))"
        case .missingPathValue: return "Missing value for --path"
        }
    }
}

public enum CLIParser {
    public static func parse(_ arguments: [String]) throws -> CLICommand {
        var args = arguments
        let json = args.removeAllFlags("--json")

        guard let command = args.first else { return .help }
        args.removeFirst()

        switch command {
        case "help", "--help", "-h":
            guard args.isEmpty else { throw CLIParserError.tooManyArguments(args) }
            return .help
        case "status":
            guard args.isEmpty else { throw CLIParserError.tooManyArguments(args) }
            return .status(json: json)
        case "list":
            guard args.isEmpty else { throw CLIParserError.tooManyArguments(args) }
            return .list(json: json)
        case "show":
            guard args.isEmpty else { throw CLIParserError.tooManyArguments(args) }
            return .show
        case "hide":
            guard args.isEmpty else { throw CLIParserError.tooManyArguments(args) }
            return .hide
        case "toggle":
            guard args.isEmpty else { throw CLIParserError.tooManyArguments(args) }
            return .toggle
        case "rescan":
            guard args.isEmpty else { throw CLIParserError.tooManyArguments(args) }
            return .rescan
        case "open-settings":
            guard args.isEmpty else { throw CLIParserError.tooManyArguments(args) }
            return .openSettings
        case "permissions":
            guard args.isEmpty else { throw CLIParserError.tooManyArguments(args) }
            return .permissions
        case "launch-at-login":
            guard let subcommand = args.first else { return .launchAtLoginStatus(json: json) }
            args.removeFirst()
            switch subcommand {
            case "status":
                guard args.isEmpty else { throw CLIParserError.tooManyArguments(args) }
                return .launchAtLoginStatus(json: json)
            case "enable", "on":
                guard args.isEmpty else { throw CLIParserError.tooManyArguments(args) }
                return .launchAtLoginEnable
            case "disable", "off":
                guard args.isEmpty else { throw CLIParserError.tooManyArguments(args) }
                return .launchAtLoginDisable
            default:
                throw CLIParserError.unknownCommand("launch-at-login \(subcommand)")
            }
        case "install-cli":
            let parsed = try parseInstallOptions(args)
            return .installCLI(path: parsed.path, force: parsed.force)
        case "uninstall-cli":
            let parsed = try parseInstallOptions(args, allowForce: false)
            return .uninstallCLI(path: parsed.path)
        case "set":
            guard let itemId = args.first else { throw CLIParserError.missingItemId }
            args.removeFirst()
            guard let modeValue = args.first else { throw CLIParserError.missingMode }
            args.removeFirst()
            guard args.isEmpty else { throw CLIParserError.tooManyArguments(args) }
            guard let mode = VisibilityMode.parse(modeValue) else { throw CLIParserError.invalidMode(modeValue) }
            return .set(itemId: itemId, mode: mode)
        default:
            throw CLIParserError.unknownCommand(command)
        }
    }
    private static func parseInstallOptions(_ args: [String], allowForce: Bool = true) throws -> (path: String?, force: Bool) {
        var remaining = args
        var path: String?
        var force = false

        while let arg = remaining.first {
            remaining.removeFirst()
            switch arg {
            case "--force" where allowForce:
                force = true
            case "--path":
                guard let value = remaining.first else { throw CLIParserError.missingPathValue }
                remaining.removeFirst()
                path = value
            default:
                throw CLIParserError.tooManyArguments([arg] + remaining)
            }
        }

        return (path, force)
    }
}

public enum CLIInstallDefaults {
    public static let defaultSymlinkPath = "/usr/local/bin/barshelf"
}

private extension Array where Element == String {
    mutating func removeAllFlags(_ flag: String) -> Bool {
        let originalCount = count
        self = filter { $0 != flag }
        return count != originalCount
    }
}
