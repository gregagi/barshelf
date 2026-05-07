import XCTest
@testable import BarShelfCore

final class VisibilityModeTests: XCTestCase {
    func testLabelsMatchSettingsCopy() {
        XCTAssertEqual(VisibilityMode.alwaysShown.label, "Always shown")
        XCTAssertEqual(VisibilityMode.floatingShelf.label, "Floating shelf")
        XCTAssertEqual(VisibilityMode.alwaysHidden.label, "Always hidden")
    }

    func testAllModesAreAvailableInSettingsOrder() {
        XCTAssertEqual(VisibilityMode.allCases, [.alwaysShown, .floatingShelf, .alwaysHidden])
    }
}

final class MenuBarItemIdentityTests: XCTestCase {
    func testDisplayNameFallsBackToOwnerWhenWindowNameIsEmpty() {
        let identity = MenuBarItemIdentity(owner: "Dropbox", name: "", roundedX: 1170)

        XCTAssertEqual(identity.displayName, "Dropbox")
        XCTAssertEqual(identity.id, "Dropbox|status-item|1170")
    }

    func testDisplayNameIncludesOwnerAndWindowNameWhenAvailable() {
        let identity = MenuBarItemIdentity(owner: "Calendar", name: "Next Meeting", roundedX: 932)

        XCTAssertEqual(identity.displayName, "Calendar — Next Meeting")
        XCTAssertEqual(identity.id, "Calendar|Next Meeting|932")
    }
}

final class VisibilityModeCodecTests: XCTestCase {
    func testRoundTripPersistsPerItemModes() throws {
        let modes = [
            "Dropbox|status-item|1170": VisibilityMode.floatingShelf,
            "Calendar|Next Meeting|932": VisibilityMode.alwaysHidden
        ]

        let data = try VisibilityModeCodec.encode(modes)
        let decoded = VisibilityModeCodec.decode(data)

        XCTAssertEqual(decoded, modes)
    }

    func testDecodeHandlesMissingOrInvalidDataSafely() {
        XCTAssertEqual(VisibilityModeCodec.decode(nil), [:])
        XCTAssertEqual(VisibilityModeCodec.decode(Data("not-json".utf8)), [:])
    }

    func testDecodeDropsUnknownModesWithoutDroppingValidEntries() throws {
        let raw = [
            "valid": "floatingShelf",
            "future-mode": "shownOnHover"
        ]
        let data = try JSONEncoder().encode(raw)

        XCTAssertEqual(VisibilityModeCodec.decode(data), ["valid": .floatingShelf])
    }
}

final class VisibilityModeCLITests: XCTestCase {
    func testParsesCLIAndRawModeNames() {
        XCTAssertEqual(VisibilityMode.parse("always-shown"), .alwaysShown)
        XCTAssertEqual(VisibilityMode.parse("floating-shelf"), .floatingShelf)
        XCTAssertEqual(VisibilityMode.parse("always-hidden"), .alwaysHidden)
        XCTAssertEqual(VisibilityMode.parse("floatingShelf"), .floatingShelf)
    }
}

final class CLIParserTests: XCTestCase {
    func testParsesStatusAndListJSONFlags() throws {
        XCTAssertEqual(try CLIParser.parse(["status", "--json"]), .status(json: true))
        XCTAssertEqual(try CLIParser.parse(["list", "--json"]), .list(json: true))
        XCTAssertEqual(try CLIParser.parse(["status"]), .status(json: false))
    }

    func testParsesLiveCommands() throws {
        XCTAssertEqual(try CLIParser.parse(["show"]), .show)
        XCTAssertEqual(try CLIParser.parse(["hide"]), .hide)
        XCTAssertEqual(try CLIParser.parse(["toggle"]), .toggle)
        XCTAssertEqual(try CLIParser.parse(["rescan"]), .rescan)
        XCTAssertEqual(try CLIParser.parse(["open-settings"]), .openSettings)
        XCTAssertEqual(try CLIParser.parse(["permissions"]), .permissions)
    }

    func testParsesSetCommand() throws {
        XCTAssertEqual(
            try CLIParser.parse(["set", "Dropbox|status-item|1170", "floating-shelf"]),
            .set(itemId: "Dropbox|status-item|1170", mode: .floatingShelf)
        )
    }

    func testRejectsInvalidSetMode() {
        XCTAssertThrowsError(try CLIParser.parse(["set", "id", "sometimes"])) { error in
            XCTAssertEqual(error as? CLIParserError, .invalidMode("sometimes"))
        }
    }
}

final class BarShelfSettingsStoreTests: XCTestCase {
    func testStoresModesAndLastSeenItemsInInjectedDefaults() {
        let defaults = UserDefaults(suiteName: "com.gregagi.barshelf.tests.\(UUID().uuidString)")!
        var store = BarShelfSettingsStore(defaults: defaults)
        let item = MenuBarItemSnapshot(id: "Dropbox|status-item|1170", owner: "Dropbox", name: "", x: 1170)

        store.lastSeenItems = [item]
        store.setMode(.alwaysHidden, for: item.id)
        store.shelfVisible = true
        store.useAdvancedRouting = false

        XCTAssertEqual(store.lastSeenItems, [item])
        XCTAssertEqual(store.mode(for: item.id), .alwaysHidden)
        XCTAssertTrue(store.shelfVisible)
        XCTAssertFalse(store.useAdvancedRouting)
        XCTAssertNotNil(store.lastScanAt)
    }
}
