import AppKit
import XCTest

@testable import Nab

@MainActor
final class DragDropBridgesTests: XCTestCase {
    private final class PromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
        func filePromiseProvider(
            _ filePromiseProvider: NSFilePromiseProvider,
            fileNameForType fileType: String
        ) -> String {
            "promised.txt"
        }

        func filePromiseProvider(
            _ filePromiseProvider: NSFilePromiseProvider,
            writePromiseTo url: URL,
            completionHandler: @escaping (Error?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    func testMaterializedImageDragPublishesAFileURL() {
        let entry = FileEntry(
            url: URL(fileURLWithPath: "/tmp/materialized.png"),
            isMaterializedByNab: true
        )

        let writer = FileDragSourceView.pasteboardWriter(for: entry)

        XCTAssertTrue(writer is NSURL)
        XCTAssertTrue(
            writer.writableTypes(for: NSPasteboard(name: .drag)).contains(.fileURL)
        )
    }

    func testDropViewRegistersEveryFilePromiseType() {
        let view = ShelfDropTarget.DropView(frame: .zero)
        let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map {
            NSPasteboard.PasteboardType($0)
        }

        XCTAssertTrue(Set(promiseTypes).isSubset(of: Set(view.registeredDraggedTypes)))
        XCTAssertTrue(view.registeredDraggedTypes.contains(.fileURL))
    }

    func testShelfOriginatingDragIsRejected() {
        XCTAssertTrue(
            ShelfDropTarget.DropView.dragOperation(forSource: FileDragSourceView()).isEmpty
        )
        XCTAssertEqual(
            ShelfDropTarget.DropView.dragOperation(forSource: NSObject()),
            .copy
        )
    }

    func testMixedPasteboardPlansEachItemIndependently() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("direct.txt")
        try Data("direct".utf8).write(to: fileURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let promiseDelegate = PromiseDelegate()
        let promise = NSFilePromiseProvider(fileType: "public.plain-text", delegate: promiseDelegate)
        let image = NSPasteboardItem()
        image.setData(Data("image".utf8), forType: .png)
        let pasteboard = NSPasteboard(name: .init("dev.nab.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let writers: [NSPasteboardWriting] = [promise, fileURL as NSURL, image]
        pasteboard.writeObjects(writers)

        let plans = ShelfDropTarget.DropView().makeDropPlans(from: pasteboard)

        XCTAssertEqual(plans.count, 3)
        guard case .filePromise = plans[0] else {
            return XCTFail("Expected the promised-file item to use its promise")
        }
        guard case .fileURL(let plannedURL) = plans[1] else {
            return XCTFail("Expected the direct-file item to use its URL")
        }
        XCTAssertEqual(plannedURL, fileURL)
        guard case .image(let pendingImage) = plans[2] else {
            return XCTFail("Expected the image item to use its image data")
        }
        XCTAssertEqual(pendingImage.data, Data("image".utf8))
        withExtendedLifetime(promiseDelegate) {}
    }

    func testFileURLWinsOverImageDataForTheSameItem() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("file".utf8).write(to: fileURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }
        let item = NSPasteboardItem()
        item.setString(fileURL.absoluteString, forType: .fileURL)
        item.setData(Data("image".utf8), forType: .png)
        let pasteboard = NSPasteboard(name: .init("dev.nab.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        let plans = ShelfDropTarget.DropView().makeDropPlans(from: pasteboard)

        XCTAssertEqual(plans.count, 1)
        guard case .fileURL(let plannedURL) = plans[0] else {
            return XCTFail("Expected one representation for the pasteboard item")
        }
        XCTAssertEqual(plannedURL, fileURL)
    }

    func testFilePromiseReaderHopsFromOperationQueueToMainActor() async {
        let callback = expectation(description: "file-promise callback")
        let expectedURL = URL(fileURLWithPath: "/tmp/promised-file")
        let reader = ShelfDropTarget.DropView.filePromiseReader { fileURL, error in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(fileURL, expectedURL)
            XCTAssertNil(error)
            callback.fulfill()
        }

        let queue = OperationQueue()
        queue.addOperation {
            reader(expectedURL, nil)
        }

        await fulfillment(of: [callback], timeout: 1)
    }

    func testPromiseDropWaitsForEveryFileFromAReceiver() {
        var state = ShelfDropTarget.DropView.PromiseDropState(receiverCount: 1)
        state.configureReceiver(
            at: 0,
            fileNames: ["first.txt", "second.txt"],
            fileTypeCount: 1
        )

        let firstURL = URL(fileURLWithPath: "/tmp/first.txt")
        state.record(FileEntry(url: firstURL), fileURL: firstURL, for: 0)

        XCTAssertFalse(state.isComplete)

        let secondURL = URL(fileURLWithPath: "/tmp/second.txt")
        state.record(FileEntry(url: secondURL), fileURL: secondURL, for: 0)

        XCTAssertTrue(state.isComplete)
    }

    func testPromiseDropPreservesReceiverAndFileOrder() {
        var state = ShelfDropTarget.DropView.PromiseDropState(receiverCount: 2)
        state.configureReceiver(
            at: 0,
            fileNames: ["first.txt", "second.txt"],
            fileTypeCount: 2
        )
        state.configureReceiver(
            at: 1,
            fileNames: ["third.txt"],
            fileTypeCount: 1
        )
        let firstURL = URL(fileURLWithPath: "/tmp/first.txt")
        let secondURL = URL(fileURLWithPath: "/tmp/second.txt")
        let thirdURL = URL(fileURLWithPath: "/tmp/third.txt")

        state.record(FileEntry(url: secondURL), fileURL: secondURL, for: 0)
        state.record(FileEntry(url: thirdURL), fileURL: thirdURL, for: 1)
        state.record(FileEntry(url: firstURL), fileURL: firstURL, for: 0)

        XCTAssertTrue(state.isComplete)
        XCTAssertEqual(
            state.result.successfulEntries.map(\.url),
            [firstURL, secondURL, thirdURL]
        )
    }

    func testPromiseDropCountsErrorsBeforeCompleting() {
        var state = ShelfDropTarget.DropView.PromiseDropState(receiverCount: 1)
        state.configureReceiver(
            at: 0,
            fileNames: ["failed.txt", "kept.txt"],
            fileTypeCount: 1
        )
        let failedURL = URL(fileURLWithPath: "/tmp/failed.txt")
        let keptURL = URL(fileURLWithPath: "/tmp/kept.txt")

        let failure = InboundDropFailure(errorDescription: "The first file failed.")
        state.recordFailure(failure, fileURL: failedURL, for: 0)
        XCTAssertFalse(state.isComplete)

        state.record(FileEntry(url: keptURL), fileURL: keptURL, for: 0)

        XCTAssertTrue(state.isComplete)
        XCTAssertEqual(state.result.successfulEntries.map(\.url), [keptURL])
        XCTAssertEqual(state.result.failures, [failure])
    }

    func testPromiseDropFallsBackToAdvertisedFileTypeCount() {
        var state = ShelfDropTarget.DropView.PromiseDropState(receiverCount: 1)
        state.configureReceiver(at: 0, fileNames: [], fileTypeCount: 2)
        let firstURL = URL(fileURLWithPath: "/tmp/first.txt")
        let secondURL = URL(fileURLWithPath: "/tmp/second.txt")

        state.record(FileEntry(url: firstURL), fileURL: firstURL, for: 0)
        XCTAssertFalse(state.isComplete)

        state.record(FileEntry(url: secondURL), fileURL: secondURL, for: 0)

        XCTAssertTrue(state.isComplete)
        XCTAssertEqual(state.result.successfulEntries.map(\.url), [firstURL, secondURL])
    }

    func testImageWriterReportsSuccessesAndFailuresOnMainActor() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destinationURL = directory.appendingPathComponent("dropped.png")
        let blockingParentURL = directory.appendingPathComponent("not-a-directory")
        let failedDestinationURL = blockingParentURL.appendingPathComponent("failed.png")
        let contents = Data("image data".utf8)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: blockingParentURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let callback = expectation(description: "image-write callback")
        let writer = ShelfDropTarget.DropView.imageWriter { result in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(result.successfulURLs, [destinationURL])
            XCTAssertEqual(result.failures.count, 1)
            XCTAssertFalse(result.failures[0].errorDescription.isEmpty)
            callback.fulfill()
        }

        let queue = OperationQueue()
        queue.addOperation {
            XCTAssertFalse(Thread.isMainThread)
            writer([
                .init(data: contents, destinationURL: destinationURL),
                .init(data: contents, destinationURL: failedDestinationURL),
            ])
        }

        await fulfillment(of: [callback], timeout: 1)
        XCTAssertEqual(try Data(contentsOf: destinationURL), contents)
    }

    func testPartialDropResultBuildsConciseFailureMessage() {
        let entries = [
            FileEntry(url: URL(fileURLWithPath: "/tmp/first.txt")),
            FileEntry(url: URL(fileURLWithPath: "/tmp/second.txt")),
        ]
        let result = InboundDropResult(
            successfulEntries: entries,
            failures: [InboundDropFailure(errorDescription: "Failed")]
        )

        XCTAssertEqual(result.partialFailureMessage, "2 of 3 files were parked; 1 failed.")
        XCTAssertNil(InboundDropResult(successfulEntries: entries).partialFailureMessage)
        XCTAssertNil(
            InboundDropResult(successfulEntries: [], failures: result.failures)
                .partialFailureMessage
        )
    }
}
