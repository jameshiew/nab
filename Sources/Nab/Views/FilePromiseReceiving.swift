import Foundation
import UniformTypeIdentifiers

struct PromiseDropAccumulator {
    private struct ReceivedFile {
        let fileIndex: Int?
        let entry: FileEntry?
        let failure: InboundDropFailure?
    }

    private struct ReceiverState {
        var fileNames: [String] = []
        var expectedFileCount = 1
        var receivedFiles: [ReceivedFile] = []
        var claimedFileIndices: Set<Int> = []

        var isComplete: Bool {
            receivedFiles.count >= expectedFileCount
        }
    }

    private var receivers: [ReceiverState]

    init(receiverCount: Int) {
        receivers = (0..<receiverCount).map { _ in ReceiverState() }
    }

    mutating func configureReceiver(
        at receiverIndex: Int,
        fileNames: [String],
        fileTypeCount: Int
    ) {
        precondition(receivers.indices.contains(receiverIndex))
        precondition(receivers[receiverIndex].receivedFiles.isEmpty)
        receivers[receiverIndex].fileNames = fileNames
        receivers[receiverIndex].expectedFileCount = max(
            fileNames.count,
            fileTypeCount,
            1
        )
    }

    @discardableResult
    mutating func record(
        _ entry: FileEntry,
        fileURL: URL,
        for receiverIndex: Int
    ) -> Bool {
        record(
            entry: entry,
            failure: nil,
            fileURL: fileURL,
            for: receiverIndex
        )
    }

    @discardableResult
    mutating func recordFailure(
        _ failure: InboundDropFailure,
        fileURL: URL,
        for receiverIndex: Int
    ) -> Bool {
        record(
            entry: nil,
            failure: failure,
            fileURL: fileURL,
            for: receiverIndex
        )
    }

    private mutating func record(
        entry: FileEntry?,
        failure: InboundDropFailure?,
        fileURL: URL,
        for receiverIndex: Int
    ) -> Bool {
        precondition(receivers.indices.contains(receiverIndex))
        precondition((entry == nil) != (failure == nil))
        var receiver = receivers[receiverIndex]
        let wasExpected = receiver.receivedFiles.count < receiver.expectedFileCount
        if !wasExpected {
            receiver.expectedFileCount += 1
        }

        let fileIndex: Int?
        if entry != nil,
            let index = receiver.fileNames.indices.first(where: {
                !receiver.claimedFileIndices.contains($0)
                    && receiver.fileNames[$0] == fileURL.lastPathComponent
            })
        {
            receiver.claimedFileIndices.insert(index)
            fileIndex = index
        } else {
            fileIndex = nil
        }
        receiver.receivedFiles.append(
            ReceivedFile(fileIndex: fileIndex, entry: entry, failure: failure)
        )
        receivers[receiverIndex] = receiver
        return wasExpected
    }

    var isComplete: Bool {
        receivers.allSatisfy(\.isComplete)
    }

    var result: InboundDropResult {
        let successfulEntries = receivers.flatMap { receiver in
            var entries = [FileEntry?](
                repeating: nil,
                count: receiver.expectedFileCount
            )
            var unmatchedEntries: [FileEntry] = []
            for receivedFile in receiver.receivedFiles {
                guard let entry = receivedFile.entry else { continue }
                if let fileIndex = receivedFile.fileIndex,
                    entries.indices.contains(fileIndex),
                    entries[fileIndex] == nil
                {
                    entries[fileIndex] = entry
                } else {
                    unmatchedEntries.append(entry)
                }
            }
            for entry in unmatchedEntries {
                if let index = entries.firstIndex(where: { $0 == nil }) {
                    entries[index] = entry
                } else {
                    entries.append(entry)
                }
            }
            return entries.compactMap { $0 }
        }
        let failures = receivers.flatMap { receiver in
            receiver.receivedFiles.compactMap(\.failure)
        }
        return InboundDropResult(
            successfulEntries: successfulEntries,
            failures: failures
        )
    }
}

struct LegacyEmailPromiseMonitor {
    private struct FileState: Hashable {
        let url: URL
        let fileSize: Int
        let modificationDate: Date
    }

    let expectedFileNames: [String]
    let expectedFileCount: Int
    private var previousState: [FileState]?

    init(expectedFileNames: [String], fallbackExpectedFileCount: Int) {
        self.expectedFileNames = expectedFileNames
        expectedFileCount = max(expectedFileNames.count, fallbackExpectedFileCount, 1)
    }

    mutating func completedURLs(in destinationURL: URL) -> [URL]? {
        stableURLs(in: destinationURL, requireAllFiles: true)
    }

    mutating func timeoutResult(in destinationURL: URL) -> InboundDropResult {
        let urls = stableURLs(in: destinationURL, requireAllFiles: false) ?? []
        return InboundDropResult(
            successfulEntries: urls.map {
                FileEntry(url: $0, isMaterializedByNab: true)
            },
            failures: (0..<max(0, expectedFileCount - urls.count)).map { _ in
                InboundDropFailure(errorDescription: "The promised email was not received.")
            }
        )
    }

    private mutating func stableURLs(
        in destinationURL: URL,
        requireAllFiles: Bool
    ) -> [URL]? {
        let manager = FileManager.default
        guard
            let contents = try? manager.contentsOfDirectory(
                at: destinationURL,
                includingPropertiesForKeys: [
                    .contentModificationDateKey, .fileSizeKey, .isRegularFileKey,
                ]
            )
        else {
            previousState = nil
            return nil
        }

        let emailURLs = contents.filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .emailMessage)
        }
        var claimedURLs: Set<URL> = []
        let expectedURLs = expectedFileNames.compactMap { name -> URL? in
            guard
                let match = emailURLs.first(where: {
                    !claimedURLs.contains($0)
                        && $0.lastPathComponent == URL(fileURLWithPath: name).lastPathComponent
                })
            else { return nil }
            claimedURLs.insert(match)
            return match
        }
        let remainingURLs =
            emailURLs
            .filter { !claimedURLs.contains($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let orderedURLs = expectedURLs + remainingURLs
        let currentState = orderedURLs.compactMap { url -> FileState? in
            guard
                let values = try? url.resourceValues(forKeys: [
                    .contentModificationDateKey,
                    .fileSizeKey,
                    .isRegularFileKey,
                ]),
                values.isRegularFile == true,
                let fileSize = values.fileSize,
                let modificationDate = values.contentModificationDate
            else { return nil }
            return FileState(
                url: url,
                fileSize: fileSize,
                modificationDate: modificationDate
            )
        }
        let previousFiles = Set(previousState ?? [])
        defer { previousState = currentState }
        let stableFiles = currentState.filter { previousFiles.contains($0) }
        if requireAllFiles {
            guard currentState.count >= expectedFileCount,
                stableFiles.count == currentState.count
            else { return nil }
        }
        return stableFiles.map(\.url)
    }
}
