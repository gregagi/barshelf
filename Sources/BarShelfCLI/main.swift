import BarShelfCore
import Foundation

struct CLIError: Error, CustomStringConvertible {
    let description: String
    let exitCode: Int32

    init(_ description: String, exitCode: Int32 = 1) {
        self.description = description
        self.exitCode = exitCode
    }
}

@main
struct BarShelfCLI {
    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch let error as CLIError {
            fputs("barshelf: \(error.description)\n", stderr)
            exit(error.exitCode)
        } catch let error as CLIParserError {
            fputs("barshelf: \(error.description)\n\n\(Self.usage)\n", stderr)
            exit(64)
        } catch {
            fputs("barshelf: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func run(arguments: [String]) throws {
        let command = try CLIParser.parse(arguments)
        let store = BarShelfSettingsStore()

        switch command {
        case .help:
            print(Self.usage)
        case .status(let json):
            printStatus(store: store, json: json)
        case .list(let json):
            printList(store: store, json: json)
        case .show:
            store.shelfVisible = true
            store.synchronize()
            post(.show)
            print("shown")
        case .hide:
            store.shelfVisible = false
            store.synchronize()
            post(.hide)
            print("hidden")
        case .toggle:
            store.shelfVisible.toggle()
            store.synchronize()
            post(.toggle)
            print(store.shelfVisible ? "shown" : "hidden")
        case .rescan:
            post(.rescan)
            print("rescan requested")
        case .openSettings:
            post(.openSettings)
            print("settings requested")
        case .permissions:
            post(.permissions)
            print("permission prompt requested")
        case .installCLI(let path, let force):
            let result = try installCLI(path: path, force: force)
            print("installed: \(result.linkPath) -> \(result.executablePath)")
        case .uninstallCLI(let path):
            let result = try uninstallCLI(path: path)
            print("uninstalled: \(result.linkPath)")
        case .set(let itemId, let mode):
            store.setMode(mode, for: itemId)
            store.synchronize()
            post(.rescan)
            print("\(itemId) -> \(mode.cliName)")
        }
    }


    struct InstallResult {
        let executablePath: String
        let linkPath: String
    }

    static func installCLI(path: String?, force: Bool) throws -> InstallResult {
        let executablePath = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        let linkPath = path ?? CLIInstallDefaults.defaultSymlinkPath
        let linkURL = URL(fileURLWithPath: linkPath)
        let parent = linkURL.deletingLastPathComponent()
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: executablePath) else {
            throw CLIError("cannot find current executable at \(executablePath)")
        }
        guard fileManager.fileExists(atPath: parent.path) else {
            throw CLIError("install directory does not exist: \(parent.path)")
        }
        guard fileManager.isWritableFile(atPath: parent.path) else {
            throw CLIError("install directory is not writable: \(parent.path). Try a user-writable --path, or create the symlink with sudo.", exitCode: 13)
        }

        if fileManager.fileExists(atPath: linkPath) || isSymlink(linkPath) {
            if force {
                try fileManager.removeItem(atPath: linkPath)
            } else if symlinkDestination(linkPath) == executablePath {
                return InstallResult(executablePath: executablePath, linkPath: linkPath)
            } else {
                throw CLIError("refusing to overwrite existing file: \(linkPath). Re-run with --force if this is intentional.", exitCode: 17)
            }
        }

        try fileManager.createSymbolicLink(atPath: linkPath, withDestinationPath: executablePath)
        return InstallResult(executablePath: executablePath, linkPath: linkPath)
    }

    static func uninstallCLI(path: String?) throws -> InstallResult {
        let executablePath = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        let linkPath = path ?? CLIInstallDefaults.defaultSymlinkPath
        let fileManager = FileManager.default

        guard isSymlink(linkPath) else {
            throw CLIError("not a BarShelf CLI symlink: \(linkPath)", exitCode: 66)
        }
        let destination = symlinkDestination(linkPath) ?? ""
        guard destination.hasSuffix("/barshelf") || destination == executablePath else {
            throw CLIError("refusing to remove symlink with unexpected destination: \(destination)", exitCode: 66)
        }

        try fileManager.removeItem(atPath: linkPath)
        return InstallResult(executablePath: destination, linkPath: linkPath)
    }

    static func isSymlink(_ path: String) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let type = attrs[.type] as? FileAttributeType else { return false }
        return type == .typeSymbolicLink
    }

    static func symlinkDestination(_ path: String) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: path)
    }

    static func post(_ command: BarShelfIPC.Command) {
        DistributedNotificationCenter.default().post(
            name: BarShelfIPC.notificationName,
            object: nil,
            userInfo: ["command": command.rawValue]
        )
    }

    static func printStatus(store: BarShelfSettingsStore, json: Bool) {
        let lastScanAt = store.lastScanAt?.timeIntervalSince1970
        if json {
            let payload: [String: Any?] = [
                "advancedRouting": store.useAdvancedRouting,
                "shelfVisible": store.shelfVisible,
                "knownItemCount": store.lastSeenItems.count,
                "lastScanAt": lastScanAt
            ]
            printJSONObject(payload)
        } else {
            print("advancedRouting: \(store.useAdvancedRouting)")
            print("shelfVisible: \(store.shelfVisible)")
            print("knownItemCount: \(store.lastSeenItems.count)")
            if let lastScanAt = store.lastScanAt {
                print("lastScanAt: \(ISO8601DateFormatter().string(from: lastScanAt))")
            } else {
                print("lastScanAt: never")
            }
        }
    }

    static func printList(store: BarShelfSettingsStore, json: Bool) {
        let items = store.lastSeenItems.sorted { $0.x < $1.x }
        if json {
            let payload = items.map { item in
                [
                    "id": item.id,
                    "owner": item.owner,
                    "name": item.name,
                    "displayName": item.displayName,
                    "x": item.x,
                    "mode": store.mode(for: item.id).cliName
                ] as [String: Any]
            }
            printJSONArray(payload)
        } else if items.isEmpty {
            print("No known menu bar items yet. Run BarShelf, grant permissions, then run `barshelf rescan`.")
        } else {
            for item in items {
                print("\(item.id)\t\(store.mode(for: item.id).cliName)\t\(item.displayName)")
            }
        }
    }

    static func printJSONObject(_ object: [String: Any?]) {
        let normalized = object.compactMapValues { $0 }
        if let data = try? JSONSerialization.data(withJSONObject: normalized, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            print(string)
        }
    }

    static func printJSONArray(_ array: [[String: Any]]) {
        if let data = try? JSONSerialization.data(withJSONObject: array, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            print(string)
        }
    }


    static let usage = """
    Usage:
      barshelf status [--json]
      barshelf list [--json]
      barshelf show
      barshelf hide
      barshelf toggle
      barshelf rescan
      barshelf set <item-id> <always-shown|floating-shelf|always-hidden>
      barshelf open-settings
      barshelf permissions
      barshelf install-cli [--path /usr/local/bin/barshelf] [--force]
      barshelf uninstall-cli [--path /usr/local/bin/barshelf]
    """
}
