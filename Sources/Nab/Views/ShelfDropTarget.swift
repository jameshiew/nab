import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// NSView-based drop target. Reads the raw drag pasteboard so we can see
/// `public.file-url` even when a dragged item also exposes image data — SwiftUI's
/// `.onDrop(of:)` filters the NSItemProvider to the most specific accepted type
/// and strips the file URL for items like PNG files from Finder.
struct ShelfDropTarget: NSViewRepresentable {
    let materializedFileStore: MaterializedFileStore
    let onDrop: (InboundDropResult) -> Void
    let onPromiseDropStarted: () -> Void
    let onPromiseDropFinished: () -> Void

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.materializedFileStore = materializedFileStore
        view.onDrop = onDrop
        view.onPromiseDropStarted = onPromiseDropStarted
        view.onPromiseDropFinished = onPromiseDropFinished
        return view
    }

    func updateNSView(_ nsView: DropView, context: Context) {
        nsView.materializedFileStore = materializedFileStore
        nsView.onDrop = onDrop
        nsView.onPromiseDropStarted = onPromiseDropStarted
        nsView.onPromiseDropFinished = onPromiseDropFinished
    }

    final class DropView: NSView {
        var materializedFileStore: MaterializedFileStore = .shared
        var onDrop: (InboundDropResult) -> Void = { _ in }
        var onPromiseDropStarted: () -> Void = {}
        var onPromiseDropFinished: () -> Void = {}

        private struct PromiseDrop {
            let receivers: [NSFilePromiseReceiver]
            let destinationURL: URL
            var state: PromiseDropAccumulator
        }

        struct ImageWriteResult: Equatable, Sendable {
            let successfulURLs: [URL]
            let failures: [InboundDropFailure]
        }

        private static let screenshotFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            return formatter
        }()
        private let filePromiseQueue: OperationQueue = {
            let queue = OperationQueue()
            queue.qualityOfService = .userInitiated
            return queue
        }()
        private let imageWriteQueue: OperationQueue = {
            let queue = OperationQueue()
            queue.name = AppIdentity.namespaced("dropped-image-write")
            queue.qualityOfService = .userInitiated
            queue.maxConcurrentOperationCount = 1
            return queue
        }()
        private var promiseDrops: [UUID: PromiseDrop] = [:]
        private var legacyEmailPromiseTasks: [UUID: Task<Void, Never>] = [:]

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            var types = NSFilePromiseReceiver.readableDraggedTypes.map {
                NSPasteboard.PasteboardType($0)
            }
            types.append(.fileURL)
            types.append(contentsOf: DropPasteboardInterpreter.supportedImageTypes.map(\.0))
            registerForDraggedTypes(types)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            let operation = Self.dragOperation(forSource: sender.draggingSource)
            DiagnosticsRecorder.shared.record(
                "drop_dragging_entered",
                details: [
                    "accepted": String(!operation.isEmpty),
                    "pasteboard_item_count": String(
                        sender.draggingPasteboard.pasteboardItems?.count ?? 0
                    ),
                ]
            )
            return operation
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            Self.dragOperation(forSource: sender.draggingSource)
        }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let accepted = !Self.dragOperation(forSource: sender.draggingSource).isEmpty
            DiagnosticsRecorder.shared.record(
                "drop_preparation_finished",
                details: ["accepted": String(accepted)]
            )
            return accepted
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let dropID = UUID()
            let diagnosticDropID = dropID.uuidString.lowercased()
            guard !Self.dragOperation(forSource: sender.draggingSource).isEmpty else {
                DiagnosticsRecorder.shared.record(
                    "drop_rejected_as_internal",
                    details: ["drop_id": diagnosticDropID]
                )
                ShelfFeedback.rejectedDrop()
                return false
            }

            let pasteboard = sender.draggingPasteboard
            DiagnosticsRecorder.shared.record(
                "drop_perform_started",
                details: [
                    "change_count": String(pasteboard.changeCount),
                    "drop_id": diagnosticDropID,
                    "pasteboard_item_count": String(pasteboard.pasteboardItems?.count ?? 0),
                ]
            )
            let interpreter = DropPasteboardInterpreter(
                imageDestinationURL: droppedImageURL(pathExtension:),
                recordDiagnosticEvent: { name, details in
                    DiagnosticsRecorder.shared.record(
                        name,
                        details: details.merging(["drop_id": diagnosticDropID]) { _, new in new }
                    )
                }
            )
            let plans = interpreter.plans(from: pasteboard)
            guard !plans.isEmpty else {
                DiagnosticsRecorder.shared.record(
                    "drop_finished_without_supported_items",
                    details: ["drop_id": diagnosticDropID]
                )
                return false
            }

            var receivers: [NSFilePromiseReceiver] = []
            var entries: [FileEntry] = []
            var images: [DropPasteboardInterpreter.PendingImage] = []
            for plan in plans {
                switch plan {
                case .filePromise(let receiver):
                    receivers.append(receiver)
                case .fileURL(let url):
                    entries.append(FileEntry(url: url))
                case .image(let image):
                    images.append(image)
                }
            }
            DiagnosticsRecorder.shared.record(
                "drop_plans_ready",
                details: [
                    "direct_file_count": String(entries.count),
                    "drop_id": diagnosticDropID,
                    "image_count": String(images.count),
                    "promise_count": String(receivers.count),
                ]
            )

            let receivesEmailThroughLegacyPromise = receivers.contains {
                Self.requiresLegacyEmailPromise(forFileTypes: $0.fileTypes)
            }
            var accepted =
                receivesEmailThroughLegacyPromise
                ? receiveLegacyEmailPromises(
                    from: sender,
                    fallbackExpectedFileCount: receivers.count,
                    dropID: dropID
                )
                : receiveFilePromises(receivers, dropID: dropID)
            if !entries.isEmpty {
                DiagnosticsRecorder.shared.record(
                    "drop_direct_files_delivery_started",
                    details: [
                        "drop_id": diagnosticDropID,
                        "entry_count": String(entries.count),
                    ]
                )
                onDrop(InboundDropResult(successfulEntries: entries))
                DiagnosticsRecorder.shared.record(
                    "drop_direct_files_delivery_finished",
                    details: ["drop_id": diagnosticDropID]
                )
                accepted = true
            }
            accepted = receiveImages(images, dropID: dropID) || accepted
            DiagnosticsRecorder.shared.record(
                "drop_perform_finished",
                details: [
                    "accepted": String(accepted),
                    "drop_id": diagnosticDropID,
                ]
            )
            return accepted
        }

        static func dragOperation(forSource source: Any?) -> NSDragOperation {
            source is FileDragSourceView ? [] : .copy
        }

        static func requiresLegacyEmailPromise(forFileTypes fileTypes: [String]) -> Bool {
            fileTypes.contains { rawType in
                UTType(rawType)?.conforms(to: .emailMessage) == true
            }
        }

        static func legacyPromisedFileNames(
            from source: AnyObject,
            at destinationURL: URL,
            selector: Selector = NSSelectorFromString(
                "namesOfPromisedFilesDroppedAtDestination:"
            )
        ) -> [String] {
            guard source.responds(to: selector),
                let result = source.perform(selector, with: destinationURL)
            else { return [] }
            return result.takeUnretainedValue() as? [String] ?? []
        }

        private func receiveLegacyEmailPromises(
            from sender: NSDraggingInfo,
            fallbackExpectedFileCount: Int,
            dropID: UUID
        ) -> Bool {
            let diagnosticDropID = dropID.uuidString.lowercased()
            let destinationURL: URL
            do {
                destinationURL = try materializedFileStore.createPromisedFileDirectory()
            } catch {
                DiagnosticsRecorder.shared.record(
                    "drop_legacy_email_promise_preparation_failed",
                    details: [
                        "drop_id": diagnosticDropID,
                        "error_type": String(reflecting: type(of: error)),
                    ]
                )
                return false
            }

            onPromiseDropStarted()
            let fileNames = Self.legacyPromisedFileNames(
                from: sender,
                at: destinationURL
            )
            DiagnosticsRecorder.shared.record(
                "drop_legacy_email_promise_monitoring_started",
                details: [
                    "drop_id": diagnosticDropID,
                    "expected_file_count": String(
                        max(fileNames.count, fallbackExpectedFileCount, 1)
                    ),
                    "returned_file_name_count": String(fileNames.count),
                ]
            )

            var monitor = LegacyEmailPromiseMonitor(
                expectedFileNames: fileNames,
                fallbackExpectedFileCount: fallbackExpectedFileCount
            )
            legacyEmailPromiseTasks[dropID] = Task { @MainActor [weak self] in
                let deadline = ContinuousClock.now + .seconds(60)
                while !Task.isCancelled, ContinuousClock.now < deadline {
                    if let urls = monitor.completedURLs(in: destinationURL) {
                        self?.finishLegacyEmailPromiseDrop(
                            dropID: dropID,
                            destinationURL: destinationURL,
                            result: InboundDropResult(
                                successfulEntries: urls.map {
                                    FileEntry(url: $0, isMaterializedByNab: true)
                                }
                            )
                        )
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard !Task.isCancelled else { return }
                self?.finishLegacyEmailPromiseDrop(
                    dropID: dropID,
                    destinationURL: destinationURL,
                    result: monitor.timeoutResult(in: destinationURL)
                )
            }
            return true
        }

        private func finishLegacyEmailPromiseDrop(
            dropID: UUID,
            destinationURL: URL,
            result: InboundDropResult
        ) {
            legacyEmailPromiseTasks.removeValue(forKey: dropID)
            if result.successfulEntries.isEmpty {
                materializedFileStore.moveToTrash([destinationURL])
            }
            DiagnosticsRecorder.shared.record(
                "drop_legacy_email_promise_delivery_started",
                details: [
                    "drop_id": dropID.uuidString.lowercased(),
                    "failure_count": String(result.failures.count),
                    "success_count": String(result.successfulEntries.count),
                ]
            )
            onDrop(result)
            onPromiseDropFinished()
        }

        private func receiveImages(
            _ images: [DropPasteboardInterpreter.PendingImage],
            dropID: UUID
        ) -> Bool {
            guard !images.isEmpty else { return false }

            let diagnosticDropID = dropID.uuidString.lowercased()
            DiagnosticsRecorder.shared.record(
                "drop_image_materialization_queued",
                details: [
                    "drop_id": diagnosticDropID,
                    "image_count": String(images.count),
                    "total_byte_count": String(images.reduce(0) { $0 + $1.data.count }),
                ]
            )
            onPromiseDropStarted()
            let writer = Self.imageWriter { [self] result in
                defer { onPromiseDropFinished() }
                DiagnosticsRecorder.shared.record(
                    "drop_image_materialization_finished",
                    details: [
                        "drop_id": diagnosticDropID,
                        "failure_count": String(result.failures.count),
                        "success_count": String(result.successfulURLs.count),
                    ]
                )
                for failure in result.failures {
                    Log.shelf.error(
                        "Failed to materialize dropped image: \(failure.errorDescription, privacy: .private)"
                    )
                }
                let entries = result.successfulURLs.map {
                    FileEntry(url: $0, isMaterializedByNab: true)
                }
                DiagnosticsRecorder.shared.record(
                    "drop_image_delivery_started",
                    details: [
                        "drop_id": diagnosticDropID,
                        "entry_count": String(entries.count),
                    ]
                )
                onDrop(
                    InboundDropResult(
                        successfulEntries: entries,
                        failures: result.failures
                    )
                )
                DiagnosticsRecorder.shared.record(
                    "drop_image_delivery_finished",
                    details: ["drop_id": diagnosticDropID]
                )
            }
            let pendingImages = images
            imageWriteQueue.addOperation {
                writer(pendingImages)
            }
            return true
        }

        private func receiveFilePromises(
            _ receivers: [NSFilePromiseReceiver],
            dropID: UUID
        ) -> Bool {
            guard !receivers.isEmpty else { return false }

            let diagnosticDropID = dropID.uuidString.lowercased()
            DiagnosticsRecorder.shared.record(
                "drop_file_promise_preparation_started",
                details: [
                    "drop_id": diagnosticDropID,
                    "receiver_count": String(receivers.count),
                ]
            )
            let destination: URL
            do {
                destination = try materializedFileStore.createPromisedFileDirectory()
            } catch {
                DiagnosticsRecorder.shared.record(
                    "drop_file_promise_preparation_failed",
                    details: [
                        "drop_id": diagnosticDropID,
                        "error_type": String(reflecting: type(of: error)),
                    ]
                )
                Log.shelf.error(
                    "Failed to prepare promised-file drop: \(error.localizedDescription, privacy: .private)"
                )
                return false
            }

            var state = PromiseDropAccumulator(receiverCount: receivers.count)
            onPromiseDropStarted()
            for (receiverIndex, receiver) in receivers.enumerated() {
                DiagnosticsRecorder.shared.record(
                    "drop_file_promise_receiver_started",
                    details: [
                        "advertised_file_count": String(receiver.fileNames.count),
                        "advertised_type_count": String(receiver.fileTypes.count),
                        "drop_id": diagnosticDropID,
                        "receiver_index": String(receiverIndex),
                    ]
                )
                let reader = Self.filePromiseReader { [weak self] fileURL, error in
                    self?.promisedFileDidArrive(
                        fileURL,
                        error: error,
                        for: dropID,
                        receiverIndex: receiverIndex
                    )
                }
                receiver.receivePromisedFiles(
                    atDestination: destination,
                    options: [:],
                    operationQueue: filePromiseQueue,
                    reader: reader
                )
                state.configureReceiver(
                    at: receiverIndex,
                    fileNames: receiver.fileNames,
                    fileTypeCount: receiver.fileTypes.count
                )
            }
            promiseDrops[dropID] = PromiseDrop(
                receivers: receivers,
                destinationURL: destination,
                state: state
            )
            DiagnosticsRecorder.shared.record(
                "drop_file_promise_callbacks_pending",
                details: ["drop_id": diagnosticDropID]
            )
            return true
        }

        static nonisolated func filePromiseReader(
            _ action: @escaping @MainActor @Sendable (URL, Error?) -> Void
        ) -> @Sendable (URL, Error?) -> Void {
            { fileURL, error in
                Task { @MainActor in
                    action(fileURL, error)
                }
            }
        }

        static nonisolated func imageWriter(
            _ action: @escaping @MainActor @Sendable (ImageWriteResult) -> Void
        ) -> @Sendable ([DropPasteboardInterpreter.PendingImage]) -> Void {
            { images in
                var writtenURLs: [URL] = []
                var failures: [InboundDropFailure] = []
                for image in images {
                    do {
                        try FileManager.default.createDirectory(
                            at: image.destinationURL.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try image.data.write(to: image.destinationURL, options: .atomic)
                        writtenURLs.append(image.destinationURL)
                    } catch {
                        failures.append(
                            InboundDropFailure(errorDescription: error.localizedDescription)
                        )
                    }
                }
                let result = ImageWriteResult(
                    successfulURLs: writtenURLs,
                    failures: failures
                )
                Task { @MainActor in
                    action(result)
                }
            }
        }

        private func promisedFileDidArrive(
            _ fileURL: URL,
            error: Error?,
            for dropID: UUID,
            receiverIndex: Int
        ) {
            let diagnosticDropID = dropID.uuidString.lowercased()
            DiagnosticsRecorder.shared.record(
                "drop_file_promise_callback_started",
                details: [
                    "drop_id": diagnosticDropID,
                    "has_error": String(error != nil),
                    "receiver_index": String(receiverIndex),
                ]
            )
            let entry: FileEntry?
            let failure: InboundDropFailure?
            if let error {
                Log.shelf.error(
                    "Failed to receive promised file: \(error.localizedDescription, privacy: .private)"
                )
                entry = nil
                failure = InboundDropFailure(errorDescription: error.localizedDescription)
            } else if FileManager.default.fileExists(atPath: fileURL.path) {
                entry = FileEntry(url: fileURL, isMaterializedByNab: true)
                failure = nil
            } else {
                Log.shelf.error(
                    "Promised file is missing at \(fileURL.path, privacy: .private(mask: .hash))"
                )
                entry = nil
                failure = InboundDropFailure(
                    errorDescription: "The promised file was not received."
                )
            }

            guard var drop = promiseDrops[dropID] else {
                DiagnosticsRecorder.shared.record(
                    "drop_file_promise_callback_after_completion",
                    details: ["drop_id": diagnosticDropID]
                )
                Log.shelf.fault("Received a promised-file callback after its drop finished")
                if let entry {
                    onDrop(InboundDropResult(successfulEntries: [entry]))
                }
                return
            }
            let wasExpected: Bool
            switch (entry, failure) {
            case (.some(let entry), nil):
                wasExpected = drop.state.record(
                    entry,
                    fileURL: fileURL,
                    for: receiverIndex
                )
            case (nil, .some(let failure)):
                wasExpected = drop.state.recordFailure(
                    failure,
                    fileURL: fileURL,
                    for: receiverIndex
                )
            default:
                preconditionFailure("Promised-file callbacks require one result")
            }
            if !wasExpected {
                DiagnosticsRecorder.shared.record(
                    "drop_file_promise_unadvertised_callback",
                    details: ["drop_id": diagnosticDropID]
                )
                Log.shelf.fault("Received more promised files than the receiver advertised")
            }

            if !drop.state.isComplete {
                DiagnosticsRecorder.shared.record(
                    "drop_file_promise_callback_recorded",
                    details: [
                        "drop_id": diagnosticDropID,
                        "receiver_index": String(receiverIndex),
                    ]
                )
                promiseDrops[dropID] = drop
                return
            }

            promiseDrops.removeValue(forKey: dropID)
            let result = drop.state.result
            if result.successfulEntries.isEmpty {
                materializedFileStore.moveToTrash([drop.destinationURL])
            }
            DiagnosticsRecorder.shared.record(
                "drop_file_promise_delivery_started",
                details: [
                    "drop_id": diagnosticDropID,
                    "failure_count": String(result.failures.count),
                    "success_count": String(result.successfulEntries.count),
                ]
            )
            onDrop(result)
            DiagnosticsRecorder.shared.record(
                "drop_file_promise_delivery_finished",
                details: ["drop_id": diagnosticDropID]
            )
            onPromiseDropFinished()
        }

        private func droppedImageURL(pathExtension: String) -> URL {
            let filename =
                "Screenshot \(Self.screenshotFormatter.string(from: Date()))-\(UUID().uuidString).\(pathExtension)"
            return materializedFileStore.droppedImageURL(filename: filename)
        }
    }
}
