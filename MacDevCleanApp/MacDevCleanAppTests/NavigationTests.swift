import XCTest

@testable import MacDevClean

/// Guards the routing table.
///
/// Large Files was built in full — screen, model, scanner, ten tests — and the
/// application went on telling the owner it did not exist, because the route
/// stayed pointed at a placeholder written when that was true. No test could
/// have caught it, because routing was a `switch` inside a view body. These
/// tests exist so the next one is caught.
@MainActor
final class NavigationTests: XCTestCase {
    func testEveryDestinationOfferedInTheSidebarHasAScreen() {
        for destination in Destination.sidebarItems {
            XCTAssertNotEqual(
                destination.screenKind, .placeholder,
                "\(destination.rawValue) is offered in the sidebar but shows a placeholder")
        }
    }

    func testAnUnavailableDestinationIsNotOfferedAtAll() {
        for destination in Destination.allCases where destination.screenKind == .placeholder {
            XCTAssertFalse(
                Destination.sidebarItems.contains(destination),
                "\(destination.rawValue) has no screen and must not be offered")
        }
    }

    /// The specific defect: Large Files is a built feature, so it must be
    /// offered and it must route to its own screen.
    func testLargeFilesRoutesToTheScreenThatWasAlreadyBuilt() {
        XCTAssertEqual(Destination.largeFiles.screenKind, .largeFiles)
        XCTAssertTrue(Destination.sidebarItems.contains(.largeFiles))
    }

    /// Every destination the app knows about is either offered or explicitly
    /// unavailable. This fails if a case is added without deciding which.
    func testEveryDestinationIsAccountedFor() {
        XCTAssertEqual(Destination.allCases.count, 6)
        for destination in Destination.allCases {
            XCTAssertEqual(
                destination.isAvailable, Destination.sidebarItems.contains(destination),
                "\(destination.rawValue) disagrees with its own availability")
        }
    }

    /// A screen kind that no destination maps to is dead routing: the detail
    /// area would carry a branch nothing can reach.
    func testNoScreenKindIsUnreachable() {
        let routed = Set(Destination.allCases.map(\.screenKind))
        for kind in Destination.ScreenKind.allCases where kind != .placeholder {
            XCTAssertTrue(routed.contains(kind), "\(kind.rawValue) is routed from no destination")
        }
    }
}
