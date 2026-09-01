import AppKit
import XCTest

@testable import Nab

@MainActor
final class DragDropBridgesTests: XCTestCase {
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
}
