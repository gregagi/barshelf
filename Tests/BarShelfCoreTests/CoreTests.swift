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

final class MenuBarItemCandidateFilterTests: XCTestCase {
    func testAcceptsStatusWindowLevelMenuBarSizedItems() {
        let candidate = MenuBarItemCandidate(layer: 25, x: 1080, y: 0, width: 28, height: 24, alpha: 1, owner: "Dropbox", title: "")

        XCTAssertTrue(MenuBarItemCandidateFilter.accepts(candidate))
    }

    func testRejectsNonStatusWindowsAndWindowServerWindows() {
        let normalWindow = MenuBarItemCandidate(layer: 0, x: 0, y: 80, width: 800, height: 600, alpha: 1, owner: "Safari", title: "")
        let menuBarBackground = MenuBarItemCandidate(layer: 25, x: 0, y: 0, width: 1440, height: 24, alpha: 1, owner: "Window Server", title: "Menubar")

        XCTAssertFalse(MenuBarItemCandidateFilter.accepts(normalWindow))
        XCTAssertFalse(MenuBarItemCandidateFilter.accepts(menuBarBackground))
    }
}

final class AXMenuBarItemCandidateFilterTests: XCTestCase {
    func testAcceptsMenuBarSizedAccessibilityItems() {
        XCTAssertTrue(AXMenuBarItemCandidateFilter.accepts(x: 1110, y: 0, width: 28, height: 24))
    }

    func testRejectsNonMenuBarAccessibilityItems() {
        XCTAssertFalse(AXMenuBarItemCandidateFilter.accepts(x: 10, y: 120, width: 300, height: 60))
        XCTAssertFalse(AXMenuBarItemCandidateFilter.accepts(x: 10, y: 0, width: 0, height: 24))
    }
}

final class AppleMenuExtraNameMapperTests: XCTestCase {
    func testMapsKnownControlCenterIdentifiersToReadableNames() {
        XCTAssertEqual(AppleMenuExtraNameMapper.displayName(for: "AudioVideoModule"), "Audio/Video")
        XCTAssertEqual(AppleMenuExtraNameMapper.displayName(for: "com.apple.menuextra.TimeMachine"), "Time Machine")
        XCTAssertEqual(AppleMenuExtraNameMapper.displayName(for: "WiFi"), "Wi-Fi")
    }

    func testUnknownNamesAreNotMapped() {
        XCTAssertNil(AppleMenuExtraNameMapper.displayName(for: "SomeFutureMenuExtra"))
    }

    func testMapsReadableNamesToSymbols() {
        XCTAssertEqual(AppleMenuExtraNameMapper.symbolName(for: "Wi-Fi"), "wifi")
        XCTAssertEqual(AppleMenuExtraNameMapper.symbolName(for: "Battery"), "battery.75percent")
    }
}

final class MenuBarItemOrderingTests: XCTestCase {
    func testMovesItemBeforeTarget() {
        XCTAssertEqual(MenuBarItemOrdering.orderedIds(afterMoving: "c", before: "b", in: ["a", "b", "c"]), ["a", "c", "b"])
    }

    func testMovesItemToEndWhenNoTarget() {
        XCTAssertEqual(MenuBarItemOrdering.orderedIds(afterMoving: "a", before: nil, in: ["a", "b", "c"]), ["b", "c", "a"])
    }
}

final class FloatingShelfLayoutCalculatorTests: XCTestCase {
    func testPositionsShelfBelowMenuBarUsingVisibleFrame() {
        let frame = FloatingShelfLayoutCalculator.frame(
            itemCount: 4,
            screenMinX: 0,
            screenMaxX: 1440,
            visibleFrameMaxY: 876,
            anchorMidX: 1300
        )

        XCTAssertEqual(frame.height, 48)
        XCTAssertEqual(frame.y, 820)
        XCTAssertGreaterThanOrEqual(frame.x, 8)
        XCTAssertLessThanOrEqual(frame.x + frame.width, 1432)
    }

    func testClampsShelfToScreenWhenAnchoredNearRightEdge() {
        let frame = FloatingShelfLayoutCalculator.frame(
            itemCount: 10,
            screenMinX: 0,
            screenMaxX: 500,
            visibleFrameMaxY: 476,
            anchorMidX: 490
        )

        XCTAssertEqual(frame.x + frame.width, 492)
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
        let store = BarShelfSettingsStore(defaults: defaults)
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

    func testDefaultsStoreUsesStandardDefaultsInsideMainAppBundle() {
        XCTAssertTrue(BarShelfDefaults.store(mainBundleIdentifier: BarShelfDefaults.suiteName) === UserDefaults.standard)
    }
}

final class CLIInstallParserTests: XCTestCase {
    func testParsesInstallCLIWithDefaults() throws {
        XCTAssertEqual(try CLIParser.parse(["install-cli"]), .installCLI(path: nil, force: false))
    }

    func testParsesInstallCLIWithPathAndForce() throws {
        XCTAssertEqual(
            try CLIParser.parse(["install-cli", "--path", "/tmp/barshelf", "--force"]),
            .installCLI(path: "/tmp/barshelf", force: true)
        )
    }

    func testParsesUninstallCLIWithPath() throws {
        XCTAssertEqual(
            try CLIParser.parse(["uninstall-cli", "--path", "/tmp/barshelf"]),
            .uninstallCLI(path: "/tmp/barshelf")
        )
    }

    func testRejectsMissingInstallPathValue() {
        XCTAssertThrowsError(try CLIParser.parse(["install-cli", "--path"])) { error in
            XCTAssertEqual(error as? CLIParserError, .missingPathValue)
        }
    }
}

final class LaunchAtLoginCLIParserTests: XCTestCase {
    func testParsesLaunchAtLoginStatus() throws {
        XCTAssertEqual(try CLIParser.parse(["launch-at-login"]), .launchAtLoginStatus(json: false))
        XCTAssertEqual(try CLIParser.parse(["launch-at-login", "status", "--json"]), .launchAtLoginStatus(json: true))
    }

    func testParsesLaunchAtLoginEnableDisable() throws {
        XCTAssertEqual(try CLIParser.parse(["launch-at-login", "enable"]), .launchAtLoginEnable)
        XCTAssertEqual(try CLIParser.parse(["launch-at-login", "on"]), .launchAtLoginEnable)
        XCTAssertEqual(try CLIParser.parse(["launch-at-login", "disable"]), .launchAtLoginDisable)
        XCTAssertEqual(try CLIParser.parse(["launch-at-login", "off"]), .launchAtLoginDisable)
    }
}
