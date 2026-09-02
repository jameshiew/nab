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

    func testPasteboardInterpreterKeepsDirectURLAndFilePromise() throws {
        let fileURL = try makeTemporaryFile(named: "direct.txt")
        let promiseDelegate = PromiseDelegate()
        let promise = NSFilePromiseProvider(
            fileType: "public.plain-text",
            delegate: promiseDelegate
        )
        let pasteboard = makePasteboard(with: [fileURL as NSURL, promise])

        let plans = makeInterpreter().plans(from: pasteboard)

        XCTAssertEqual(plans.count, 2)
        guard case .fileURL(let plannedURL) = plans[0] else {
            return XCTFail("Expected the direct file URL first")
        }
        XCTAssertEqual(plannedURL, fileURL)
        guard case .filePromise = plans[1] else {
            return XCTFail("Expected the file promise second")
        }
        withExtendedLifetime(promiseDelegate) {}
    }

    func testPasteboardInterpreterKeepsDirectURLAndRawImage() throws {
        let fileURL = try makeTemporaryFile(named: "direct.txt")
        let imageData = Data("image".utf8)
        let image = NSPasteboardItem()
        image.setData(imageData, forType: .png)
        let pasteboard = makePasteboard(with: [fileURL as NSURL, image])

        let plans = makeInterpreter().plans(from: pasteboard)

        XCTAssertEqual(plans.count, 2)
        guard case .fileURL(let plannedURL) = plans[0] else {
            return XCTFail("Expected the direct file URL first")
        }
        XCTAssertEqual(plannedURL, fileURL)
        guard case .image(let pendingImage) = plans[1] else {
            return XCTFail("Expected the raw image second")
        }
        XCTAssertEqual(pendingImage.data, imageData)
    }

    func testShelfOriginatingMixedDragIsRejected() throws {
        let fileURL = try makeTemporaryFile(named: "direct.txt")
        let image = NSPasteboardItem()
        image.setData(Data("image".utf8), forType: .png)
        let pasteboard = makePasteboard(with: [fileURL as NSURL, image])

        XCTAssertEqual(makeInterpreter().plans(from: pasteboard).count, 2)
        XCTAssertTrue(
            ShelfDropTarget.DropView.dragOperation(forSource: FileDragSourceView()).isEmpty
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

        let plans = makeInterpreter().plans(from: pasteboard)

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

        let plans = makeInterpreter().plans(from: pasteboard)

        XCTAssertEqual(plans.count, 1)
        guard case .fileURL(let plannedURL) = plans[0] else {
            return XCTFail("Expected one representation for the pasteboard item")
        }
        XCTAssertEqual(plannedURL, fileURL)
    }

    func testMissingFileURLFallsBackToImageDataForTheSameItem() {
        let item = NSPasteboardItem()
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let imageData = Data("image".utf8)
        item.setString(missingURL.absoluteString, forType: .fileURL)
        item.setData(imageData, forType: .png)
        let pasteboard = makePasteboard(with: [item])

        let plans = makeInterpreter().plans(from: pasteboard)

        XCTAssertEqual(plans.count, 1)
        guard case .image(let pendingImage) = plans[0] else {
            return XCTFail("Expected image data after rejecting the missing file URL")
        }
        XCTAssertEqual(pendingImage.data, imageData)
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

    func testPromisePlanCanBeginFulfillmentThroughBackingPasteboard() throws {
        let promiseDelegate = PromiseDelegate()
        let promise = NSFilePromiseProvider(
            fileType: "public.plain-text",
            delegate: promiseDelegate
        )
        let pasteboard = makePasteboard(with: [promise])
        let plans = makeInterpreter().plans(from: pasteboard)
        guard case .filePromise(let receiver) = try XCTUnwrap(plans.first) else {
            return XCTFail("Expected a file promise")
        }
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        let operationQueue = OperationQueue()

        receiver.receivePromisedFiles(
            atDestination: destinationURL,
            options: [:],
            operationQueue: operationQueue,
            reader: { _, _ in }
        )

        XCTAssertEqual(receiver.fileTypes, ["public.plain-text"])
        withExtendedLifetime((promiseDelegate, promise, pasteboard, operationQueue)) {}
    }

    func testPromiseAccumulatorWaitsForTwoSuccessfulCallbacksFromOneReceiver() {
        var state = PromiseDropAccumulator(receiverCount: 1)
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

    func testPromiseAccumulatorPreservesSourceOrderWhenCallbacksCompleteOutOfOrder() {
        var state = PromiseDropAccumulator(receiverCount: 2)
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

    func testPromiseAccumulatorWaitsForSuccessAfterErrorCallback() {
        var state = PromiseDropAccumulator(receiverCount: 1)
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

    func testPartiallyFailedPromiseDropRequestsVisibleFeedback() {
        var state = PromiseDropAccumulator(receiverCount: 1)
        state.configureReceiver(
            at: 0,
            fileNames: ["failed.txt", "kept.txt"],
            fileTypeCount: 2
        )
        let failure = InboundDropFailure(errorDescription: "The first file failed.")
        let failedURL = URL(fileURLWithPath: "/tmp/failed.txt")
        let keptURL = URL(fileURLWithPath: "/tmp/kept.txt")
        state.recordFailure(failure, fileURL: failedURL, for: 0)
        state.record(FileEntry(url: keptURL), fileURL: keptURL, for: 0)
        var addedEntries: [FileEntry] = []
        var rejected = false
        var dropReceived = false
        var reportedResult: InboundDropResult?
        let handler = ShelfDropResultHandler(
            addEntries: {
                addedEntries = $0
                return (added: $0.count, duplicates: 0)
            },
            rejectDrop: { rejected = true },
            onDropReceived: { dropReceived = true },
            onDropPartiallyFailed: { reportedResult = $0 }
        )

        handler.handle(state.result)

        XCTAssertEqual(addedEntries.map(\.url), [keptURL])
        XCTAssertFalse(rejected)
        XCTAssertTrue(dropReceived)
        XCTAssertEqual(reportedResult, state.result)
    }

    func testTotallyFailedPromiseDropRequestsRejectionFeedback() {
        var state = PromiseDropAccumulator(receiverCount: 1)
        state.configureReceiver(
            at: 0,
            fileNames: ["failed.txt"],
            fileTypeCount: 1
        )
        state.recordFailure(
            InboundDropFailure(errorDescription: "The file failed."),
            fileURL: URL(fileURLWithPath: "/tmp/failed.txt"),
            for: 0
        )
        var addedEntries: [FileEntry] = []
        var rejected = false
        var dropReceived = false
        var partialFailureReported = false
        let handler = ShelfDropResultHandler(
            addEntries: {
                addedEntries = $0
                return (added: $0.count, duplicates: 0)
            },
            rejectDrop: { rejected = true },
            onDropReceived: { dropReceived = true },
            onDropPartiallyFailed: { _ in partialFailureReported = true }
        )

        handler.handle(state.result)

        XCTAssertTrue(addedEntries.isEmpty)
        XCTAssertTrue(rejected)
        XCTAssertFalse(dropReceived)
        XCTAssertFalse(partialFailureReported)
    }

    func testDuplicateOnlyDropRequestsRejectionAndAcknowledgesDrop() {
        let entry = FileEntry(url: URL(fileURLWithPath: "/tmp/duplicate.txt"))
        var addedEntries: [FileEntry] = []
        var rejected = false
        var dropReceived = false
        var partialFailureReported = false
        let handler = ShelfDropResultHandler(
            addEntries: {
                addedEntries = $0
                return (added: 0, duplicates: $0.count)
            },
            rejectDrop: { rejected = true },
            onDropReceived: { dropReceived = true },
            onDropPartiallyFailed: { _ in partialFailureReported = true }
        )

        handler.handle(InboundDropResult(successfulEntries: [entry]))

        XCTAssertEqual(addedEntries, [entry])
        XCTAssertTrue(rejected)
        XCTAssertTrue(dropReceived)
        XCTAssertFalse(partialFailureReported)
    }

    func testPromiseAccumulatorFallsBackToAdvertisedFileTypeCount() {
        var state = PromiseDropAccumulator(receiverCount: 1)
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
        let firstDestinationURL = directory.appendingPathComponent("first.png")
        let secondDestinationURL = directory.appendingPathComponent("second.png")
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
            XCTAssertEqual(result.successfulURLs, [firstDestinationURL, secondDestinationURL])
            XCTAssertEqual(result.failures.count, 1)
            XCTAssertFalse(result.failures[0].errorDescription.isEmpty)
            callback.fulfill()
        }

        let queue = OperationQueue()
        queue.addOperation {
            XCTAssertFalse(Thread.isMainThread)
            writer([
                .init(data: contents, destinationURL: firstDestinationURL),
                .init(data: contents, destinationURL: failedDestinationURL),
                .init(data: contents, destinationURL: secondDestinationURL),
            ])
        }

        await fulfillment(of: [callback], timeout: 1)
        XCTAssertEqual(try Data(contentsOf: firstDestinationURL), contents)
        XCTAssertEqual(try Data(contentsOf: secondDestinationURL), contents)
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

    private func makeInterpreter() -> DropPasteboardInterpreter {
        DropPasteboardInterpreter { pathExtension in
            URL(fileURLWithPath: "/tmp/dropped.\(pathExtension)")
        }
    }

    private func makePasteboard(with writers: [NSPasteboardWriting]) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("dev.nab.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects(writers))
        return pasteboard
    }

    private func makeTemporaryFile(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(name)
        try Data("file".utf8).write(to: fileURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return fileURL
    }
}
