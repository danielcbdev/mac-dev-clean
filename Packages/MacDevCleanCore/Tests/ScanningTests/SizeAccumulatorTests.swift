import Domain
import XCTest

@testable import Scanning

final class SizeAccumulatorTests: XCTestCase {

    func testHardLinkBytesAreCountedOnce() throws {
        var sum = SizeAccumulator()
        let identity = FileIdentity(device: 1, inode: 2, modifiedNanoseconds: 0)
        try sum.add(logical: 100, allocated: 4096, identity: identity)
        try sum.add(logical: 100, allocated: 4096, identity: identity)
        XCTAssertEqual(sum.logicalBytes, 100)
        XCTAssertEqual(sum.allocatedBytes, 4096)
    }

    func testDistinctFilesAreBothCounted() throws {
        var sum = SizeAccumulator()
        try sum.add(
            logical: 100, allocated: 4096,
            identity: FileIdentity(device: 1, inode: 2, modifiedNanoseconds: 0))
        try sum.add(
            logical: 50, allocated: 4096,
            identity: FileIdentity(device: 1, inode: 3, modifiedNanoseconds: 0))

        XCTAssertEqual(sum.logicalBytes, 150)
        XCTAssertEqual(sum.allocatedBytes, 8192)
    }

    func testTheSameInodeOnAnotherVolumeIsADifferentFile() throws {
        var sum = SizeAccumulator()
        try sum.add(
            logical: 100, allocated: 0,
            identity: FileIdentity(device: 1, inode: 2, modifiedNanoseconds: 0))
        try sum.add(
            logical: 100, allocated: 0,
            identity: FileIdentity(device: 2, inode: 2, modifiedNanoseconds: 0))

        XCTAssertEqual(sum.logicalBytes, 200)
    }

    func testAnUnknownSizeMakesTheTotalUnknownRatherThanWrong() throws {
        var sum = SizeAccumulator()
        try sum.add(
            logical: 100, allocated: 4096,
            identity: FileIdentity(device: 1, inode: 2, modifiedNanoseconds: 0))
        try sum.add(
            logical: nil, allocated: nil,
            identity: FileIdentity(device: 1, inode: 3, modifiedNanoseconds: 0))

        XCTAssertTrue(sum.hasUnknownSizes)
        XCTAssertNil(sum.reportedLogicalBytes)
        XCTAssertNil(sum.reportedAllocatedBytes)
        // The running total is still available for diagnostics; it is simply
        // never presented as an exact answer.
        XCTAssertEqual(sum.logicalBytes, 100)
    }

    func testAKnownOnlyTotalIsReported() throws {
        var sum = SizeAccumulator()
        try sum.add(
            logical: 7, allocated: 8,
            identity: FileIdentity(device: 1, inode: 2, modifiedNanoseconds: 0))

        XCTAssertFalse(sum.hasUnknownSizes)
        XCTAssertEqual(sum.reportedLogicalBytes, 7)
        XCTAssertEqual(sum.reportedAllocatedBytes, 8)
    }

    func testOverflowThrowsRatherThanWrappingAround() throws {
        var sum = SizeAccumulator()
        try sum.add(
            logical: .max, allocated: 0,
            identity: FileIdentity(device: 1, inode: 2, modifiedNanoseconds: 0))

        XCTAssertThrowsError(
            try sum.add(
                logical: 1, allocated: 0,
                identity: FileIdentity(device: 1, inode: 3, modifiedNanoseconds: 0))
        ) { error in
            XCTAssertEqual(error as? MeasurementError, .overflow)
        }
        // The accumulator is left at its last valid value, never wrapped.
        XCTAssertEqual(sum.logicalBytes, .max)
    }

    func testAllocatedOverflowAlsoThrows() throws {
        var sum = SizeAccumulator()
        try sum.add(
            logical: 0, allocated: .max,
            identity: FileIdentity(device: 1, inode: 2, modifiedNanoseconds: 0))

        XCTAssertThrowsError(
            try sum.add(
                logical: 0, allocated: 1,
                identity: FileIdentity(device: 1, inode: 3, modifiedNanoseconds: 0))
        ) { error in
            XCTAssertEqual(error as? MeasurementError, .overflow)
        }
    }
}
