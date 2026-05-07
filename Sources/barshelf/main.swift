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
        var store = BarShelfSettingsStore()

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
        case .set(let itemId, let mode):
            store.setMode(mode, for: itemId)
            store.synchronize()
            post(.rescan)
            print("\(itemId) -> \(mode.cliName)")
        }
    }

    static func post(_ command: BarShelfIPC.Command) {
        DistributedNotificationCenter.default().post(
            name: BarShelfIPC.notificationName,
            object: nil,
            userInfo: ["command": command.rawValue],
            deliverImmediately: true
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
    """
}
