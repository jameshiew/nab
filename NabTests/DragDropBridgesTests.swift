import AppKit
import XCTest

@testable import Nab

@MainActor
final class DragDropBridgesTests: XCTestCase {
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

    func testImageWriterWritesOffMainActorAndCompletesOnMainActor() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destinationURL = directory.appendingPathComponent("dropped.png")
        let contents = Data("image data".utf8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let callback = expectation(description: "image-write callback")
        let writer = ShelfDropTarget.DropView.imageWriter { urls, errorDescriptions in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(urls, [destinationURL])
            XCTAssertTrue(errorDescriptions.isEmpty)
            callback.fulfill()
        }

        let queue = OperationQueue()
        queue.addOperation {
            XCTAssertFalse(Thread.isMainThread)
            writer([.init(data: contents, destinationURL: destinationURL)])
        }

        await fulfillment(of: [callback], timeout: 1)
        XCTAssertEqual(try Data(contentsOf: destinationURL), contents)
    }
}
