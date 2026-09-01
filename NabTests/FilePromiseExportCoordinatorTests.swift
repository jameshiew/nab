import AppKit
import Foundation
import XCTest

@testable import Nab

@MainActor
final class FilePromiseExportCoordinatorTests: XCTestCase {
    func testAcceptedExportWaitsForEveryPromiseBeforeRemovingItem() async throws {
        let directory = try makeTemporaryDirectory()
        let firstSource = try makeFile(named: "first.png", in: directory)
        let secondSource = try makeFile(named: "second.png", in: directory)
        let itemID = UUID()
        var exportedItemIDs: [[ShelfItem.ID]] = []
        var failures: [FilePromiseExportFailure] = []
        let didExport = expectation(description: "item exported")
        let coordinator = FilePromiseExportCoordinator { itemIDs in
            exportedItemIDs.append(itemIDs)
            didExport.fulfill()
        } onFailure: { failure in
            failures.append(failure)
        }

        let exportID = coordinator.beginExport()
        coordinator.registerItem(itemID, in: exportID)
        var firstDelegate: MaterializedFilePromiseDelegate? = coordinator.makePromiseDelegate(
            sourceURL: firstSource,
            itemID: itemID,
            in: exportID
        )
        var secondDelegate: MaterializedFilePromiseDelegate? = coordinator.makePromiseDelegate(
            sourceURL: secondSource,
            itemID: itemID,
            in: exportID
        )
        weak let retainedFirstDelegate = firstDelegate
        weak let retainedSecondDelegate = secondDelegate
        let firstProvider = NSFilePromiseProvider(fileType: "public.png", delegate: firstDelegate!)
        let secondProvider = NSFilePromiseProvider(fileType: "public.png", delegate: secondDelegate!)
        firstDelegate = nil
        secondDelegate = nil

        coordinator.finishExport(exportID, operation: .copy)

        XCTAssertNotNil(retainedFirstDelegate)
        XCTAssertNotNil(retainedSecondDelegate)
        XCTAssertTrue(exportedItemIDs.isEmpty)

        retainedFirstDelegate?.filePromiseProvider(
            firstProvider,
            writePromiseTo: directory.appendingPathComponent("first-copy.png")
        ) { XCTAssertNil($0) }
        await Task.yield()

        XCTAssertNil(retainedFirstDelegate)
        XCTAssertNotNil(retainedSecondDelegate)
        XCTAssertTrue(exportedItemIDs.isEmpty)

        retainedSecondDelegate?.filePromiseProvider(
            secondProvider,
            writePromiseTo: directory.appendingPathComponent("second-copy.png")
        ) { XCTAssertNil($0) }
        await fulfillment(of: [didExport], timeout: 1)

        XCTAssertNil(retainedSecondDelegate)
        XCTAssertEqual(exportedItemIDs, [[itemID]])
        XCTAssertTrue(failures.isEmpty)
    }

    func testFailedPromiseKeepsItsItemAndSurfacesError() async throws {
        let directory = try makeTemporaryDirectory()
        let successfulSource = try makeFile(named: "successful.png", in: directory)
        let failedSource = try makeFile(named: "failed.png", in: directory)
        let successfulItemID = UUID()
        let failedItemID = UUID()
        var exportedItemIDs: [[ShelfItem.ID]] = []
        var failures: [FilePromiseExportFailure] = []
        let didExport = expectation(description: "successful item exported")
        let didFail = expectation(description: "failure surfaced")
        let coordinator = FilePromiseExportCoordinator { itemIDs in
            exportedItemIDs.append(itemIDs)
            didExport.fulfill()
        } onFailure: { failure in
            failures.append(failure)
            didFail.fulfill()
        }

        let exportID = coordinator.beginExport()
        coordinator.registerItem(successfulItemID, in: exportID)
        coordinator.registerItem(failedItemID, in: exportID)
        let successfulDelegate = coordinator.makePromiseDelegate(
            sourceURL: successfulSource,
            itemID: successfulItemID,
            in: exportID
        )
        let failedDelegate = coordinator.makePromiseDelegate(
            sourceURL: failedSource,
            itemID: failedItemID,
            in: exportID
        )
        let successfulProvider = NSFilePromiseProvider(
            fileType: "public.png",
            delegate: successfulDelegate
        )
        let failedProvider = NSFilePromiseProvider(fileType: "public.png", delegate: failedDelegate)
        coordinator.finishExport(exportID, operation: .copy)

        successfulDelegate.filePromiseProvider(
            successfulProvider,
            writePromiseTo: directory.appendingPathComponent("successful-copy.png")
        ) { XCTAssertNil($0) }
        failedDelegate.filePromiseProvider(
            failedProvider,
            writePromiseTo: directory.appendingPathComponent("missing/copy.png")
        ) { XCTAssertNotNil($0) }
        await fulfillment(of: [didExport, didFail], timeout: 1)

        XCTAssertEqual(exportedItemIDs, [[successfulItemID]])
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures[0].sourceURL, failedSource)
        XCTAssertFalse(failures[0].errorDescription.isEmpty)
    }

    func testAcceptedExportWithoutPromisesRemovesItemImmediately() {
        let itemID = UUID()
        var exportedItemIDs: [[ShelfItem.ID]] = []
        let coordinator = FilePromiseExportCoordinator { itemIDs in
            exportedItemIDs.append(itemIDs)
        } onFailure: { _ in
            XCTFail("Unexpected export failure")
        }

        let exportID = coordinator.beginExport()
        coordinator.registerItem(itemID, in: exportID)
        coordinator.finishExport(exportID, operation: .copy)

        XCTAssertEqual(exportedItemIDs, [[itemID]])
    }

    func testCancelledExportReleasesUnfulfilledPromisesAndKeepsItem() throws {
        let directory = try makeTemporaryDirectory()
        let source = try makeFile(named: "source.png", in: directory)
        let itemID = UUID()
        var exportedItemIDs: [[ShelfItem.ID]] = []
        let coordinator = FilePromiseExportCoordinator { itemIDs in
            exportedItemIDs.append(itemIDs)
        } onFailure: { _ in
            XCTFail("Unexpected export failure")
        }

        let exportID = coordinator.beginExport()
        coordinator.registerItem(itemID, in: exportID)
        var delegate: MaterializedFilePromiseDelegate? = coordinator.makePromiseDelegate(
            sourceURL: source,
            itemID: itemID,
            in: exportID
        )
        weak let retainedDelegate = delegate
        delegate = nil

        coordinator.finishExport(exportID, operation: [])

        XCTAssertNil(retainedDelegate)
        XCTAssertTrue(exportedItemIDs.isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func makeFile(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(name.utf8).write(to: url)
        return url
    }
}
