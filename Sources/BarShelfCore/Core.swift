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

public enum BarShelfDefaults {
    public static let suiteName = "com.gregagi.barshelf"

    public enum Key {
        public static let collapsed = "collapsed.v1"
        public static let spacerWidth = "spacerWidth.v1"
        public static let alwaysHiddenEnabled = "alwaysHiddenEnabled.v1"
        public static let autoCollapseSeconds = "autoCollapseSeconds.v1"
        public static let itemModes = "itemModes.v2"
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
