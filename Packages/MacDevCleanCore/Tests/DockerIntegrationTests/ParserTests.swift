import Domain
import XCTest

@testable import DockerIntegration

final class ParserTests: XCTestCase {

    // MARK: - Build cache

    func testBuildCacheSizeStringAndSharedStatus() throws {
        let data = Data(
            #"{"ID":"abc123","Size":"4096","Reclaimable":true,"Shared":true,"Mutable":false}"#.utf8)
        let row = try XCTUnwrap(DockerParser.buildCache(data).first)
        XCTAssertEqual(row.size, 4096)
        XCTAssertTrue(row.shared)
    }

    func testBuildCacheFixtureIsParsedWithEligibilityAndSharing() throws {
        let rows = try DockerParser.buildCache(Self.fixture("buildx-du"))

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.map(\.id), ["cache0001", "cache0002", "cache0003"])
        XCTAssertTrue(rows[0].isEligible)
        XCTAssertFalse(rows[0].shared)
        XCTAssertTrue(rows[1].shared, "shared bytes belong to more than one record")
        XCTAssertFalse(rows[2].isEligible, "a mutable, non-reclaimable record is never eligible")

        // Shared rows stay out of an exact reclaimable total.
        let exact = rows.filter { $0.isEligible && !$0.shared }.compactMap(\.size).reduce(0, +)
        XCTAssertEqual(exact, 4096)
    }

    func testAMissingIdentifierIsRefused() {
        let data = Data(#"{"Size":"4096","Reclaimable":true}"#.utf8)
        XCTAssertThrowsError(try DockerParser.buildCache(data)) {
            XCTAssertEqual($0 as? PolicyError, .unsupported)
        }
    }

    func testMalformedJSONIsRefused() {
        XCTAssertThrowsError(try DockerParser.buildCache(Self.fixture("malformed"))) {
            XCTAssertEqual($0 as? PolicyError, .unsupported)
        }
    }

    func testUnknownFieldsAreIgnored() throws {
        let data = Data(
            #"{"ID":"abc","Size":"1","Reclaimable":true,"Shared":false,"Mutable":false,"SomethingNew":{"a":1}}"#
                .utf8)
        let row = try XCTUnwrap(DockerParser.buildCache(data).first)
        XCTAssertEqual(row.size, 1)
    }

    func testAMissingSizeIsUnknownRatherThanZero() throws {
        let data = Data(#"{"ID":"abc","Reclaimable":true,"Shared":false,"Mutable":false}"#.utf8)
        let row = try XCTUnwrap(DockerParser.buildCache(data).first)
        XCTAssertNil(row.size)
        XCTAssertNil(row.sizeIssue, "an absent field is not an anomaly, just unknown")
    }

    func testANegativeSizeIsUnknownAndReported() throws {
        let data = Data(#"{"ID":"abc","Size":"-1","Reclaimable":true}"#.utf8)
        let row = try XCTUnwrap(DockerParser.buildCache(data).first)
        XCTAssertNil(row.size)
        XCTAssertEqual(row.sizeIssue, "issue.docker.sizeNegative")
    }

    func testAnOversizedValueIsUnknownAndReported() throws {
        let data = Data(#"{"ID":"abc","Size":1e30,"Reclaimable":true}"#.utf8)
        let row = try XCTUnwrap(DockerParser.buildCache(data).first)
        XCTAssertNil(row.size)
        XCTAssertEqual(row.sizeIssue, "issue.docker.sizeOverflow")
    }

    func testAHumanReadableSizeIsNeverTurnedIntoAnExactNumber() throws {
        let data = Data(#"{"ID":"abc","Size":"1.09GB","Reclaimable":true}"#.utf8)
        let row = try XCTUnwrap(DockerParser.buildCache(data).first)
        XCTAssertNil(row.size)
        XCTAssertEqual(row.sizeIssue, "issue.docker.sizeNotExact")
    }

    func testAMissingReclaimableFlagMakesTheRecordIneligible() throws {
        let data = Data(#"{"ID":"abc","Size":"4096","Shared":false,"Mutable":false}"#.utf8)
        let row = try XCTUnwrap(DockerParser.buildCache(data).first)
        XCTAssertFalse(row.reclaimable)
        XCTAssertFalse(row.isEligible)
    }

    func testAMissingMutableFlagAlsoMakesTheRecordIneligible() throws {
        let data = Data(#"{"ID":"abc","Size":"4096","Reclaimable":true,"Shared":false}"#.utf8)
        let row = try XCTUnwrap(DockerParser.buildCache(data).first)
        XCTAssertTrue(row.mutable, "an absent boolean takes the cautious value")
        XCTAssertFalse(row.isEligible)
    }

    func testAStringIsNotAcceptedInPlaceOfABoolean() throws {
        let data = Data(#"{"ID":"abc","Size":"1","Reclaimable":"true","Mutable":"false"}"#.utf8)
        let row = try XCTUnwrap(DockerParser.buildCache(data).first)
        XCTAssertFalse(row.reclaimable, "a changed shape is refused, not coerced")
        XCTAssertFalse(row.isEligible)
    }

    // MARK: - Containers

    func testContainersAreParsedWithStateAndMounts() throws {
        let rows = try DockerParser.containers(Self.fixture("containers"))

        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows[0].isRunning)
        XCTAssertFalse(rows[1].isRunning)
        XCTAssertEqual(rows[1].mounts, ["fixture-db", "fixture-logs"])
        XCTAssertEqual(rows[2].mounts, [])
    }

    func testAnAbsentStateIsNotAssumedStopped() throws {
        let data = Data(#"{"ID":"abc","Image":"x","Names":"y"}"#.utf8)
        let row = try XCTUnwrap(DockerParser.containers(data).first)
        XCTAssertEqual(row.state, "unknown")
        XCTAssertFalse(row.isRunning)
    }

    // MARK: - Images

    func testImagesAreParsedAndDanglingOnesIdentified() throws {
        let rows = try DockerParser.images(Self.fixture("images"))

        XCTAssertEqual(rows.count, 3)
        XCTAssertFalse(rows[0].isDangling)
        XCTAssertTrue(rows[2].isDangling)
        XCTAssertTrue(rows[0].id.hasPrefix("sha256:"))
    }

    // MARK: - Volumes

    func testOnlyLocalDriverVolumesAreEligible() throws {
        let rows = try DockerParser.volumes(Self.fixture("volumes"))

        XCTAssertEqual(rows.count, 4)
        XCTAssertTrue(rows[0].isLocalDriver)
        let plugin = try XCTUnwrap(rows.first { $0.name == "fixture-remote" })
        XCTAssertFalse(
            plugin.isLocalDriver,
            "a plugin driver may be backed by storage this app knows nothing about")
    }

    func testAnUnknownDriverIsNotTreatedAsLocal() throws {
        let data = Data(#"{"Name":"v1","Mountpoint":"/x"}"#.utf8)
        let row = try XCTUnwrap(DockerParser.volumes(data).first)
        XCTAssertEqual(row.driver, "unknown")
        XCTAssertFalse(row.isLocalDriver)
    }

    // MARK: - Inspections

    func testVolumeSizeIsUnknownUnlessTheDaemonSuppliesIt() throws {
        let without = Data(#"[{"Name":"v1","Driver":"local"}]"#.utf8)
        let with = Data(
            #"[{"Name":"v1","Driver":"local","UsageData":{"Size":2048,"RefCount":1}}]"#.utf8)

        XCTAssertNil(try DockerParser.volumeDetails(without).first?.size)
        XCTAssertEqual(try DockerParser.volumeDetails(with).first?.size, 2048)
    }

    func testDockerReportingMinusOneForAnUncalculatedSizeIsUnknown() throws {
        let data = Data(
            #"[{"Name":"v1","Driver":"local","UsageData":{"Size":-1,"RefCount":1}}]"#.utf8)
        XCTAssertNil(try DockerParser.volumeDetails(data).first?.size)
    }

    func testContainerDetailKeepsItsMountsAndRunningState() throws {
        let data = Data(
            #"""
            [{"Id":"1111","Image":"sha256:aaaa","State":{"Running":false},\#
            "Mounts":[{"Name":"fixture-db","Type":"volume"}],"SizeRootFs":123456}]
            """#.utf8)

        let detail = try XCTUnwrap(DockerParser.containerDetails(data).first)
        XCTAssertFalse(detail.running)
        XCTAssertEqual(detail.mountNames, ["fixture-db"])
        XCTAssertEqual(detail.sizeRootFs, 123_456)
    }

    func testAnAbsentRunningFlagIsTreatedAsRunning() throws {
        let data = Data(#"[{"Id":"1111","Image":"sha256:aaaa","State":{}}]"#.utf8)
        let detail = try XCTUnwrap(DockerParser.containerDetails(data).first)
        XCTAssertTrue(detail.running, "not knowing must never mean safe to remove")
    }

    func testImageDetailCarriesItsTagsAndDigests() throws {
        let data = Data(
            #"""
            [{"Id":"sha256:aaaa","Size":142000000,"RepoTags":["fixture/web:latest","fixture/web:1"],\#
            "RepoDigests":["fixture/web@sha256:bbbb"]}]
            """#.utf8)

        let detail = try XCTUnwrap(DockerParser.imageDetails(data).first)
        XCTAssertEqual(detail.size, 142_000_000)
        XCTAssertEqual(detail.repoTags.count, 2)
        XCTAssertEqual(detail.repoDigests.count, 1)
    }

    // MARK: - Fixtures

    private static func fixture(_ name: String) -> Data {
        guard
            let url = Bundle.module.url(
                forResource: name, withExtension: "json",
                subdirectory: "Fixtures"),
            let data = try? Data(contentsOf: url)
        else {
            XCTFail("missing fixture \(name).json")
            return Data()
        }
        return data
    }
}
