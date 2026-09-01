import Foundation
import os

nonisolated final class MaterializedFileStore: @unchecked Sendable {
    static let shared = MaterializedFileStore()

    final class ReadLease: @unchecked Sendable {
        private let lock = NSLock()
        private var store: MaterializedFileStore?
        private let url: URL

        fileprivate init(store: MaterializedFileStore, url: URL) {
            self.store = store
            self.url = url
        }

        func finish() {
            lock.lock()
            guard let store else {
                lock.unlock()
                return
            }
            self.store = nil
            lock.unlock()
            store.endReading(url)
        }

        deinit {
            finish()
        }
    }

    private let droppedImageDirectoryURL: URL
    private let droppedFileDirectoryURL: URL
    private let trashItem: @Sendable (URL) throws -> Void
    private let cleanupQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "dev.nab.materialized-file-cleanup"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let stateLock = NSLock()
    private var readCounts: [URL: Int] = [:]
    private var pendingURLs: Set<URL> = []
    private var scheduledURLs: Set<URL> = []
    private let logger = Logger(subsystem: "dev.nab.Nab", category: "Storage")

    init(
        applicationSupportURL: URL = MaterializedFileStore.defaultApplicationSupportURL(),
        trashItem: @escaping @Sendable (URL) throws -> Void = { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    ) {
        let rootURL =
            applicationSupportURL
            .appendingPathComponent("Nab", isDirectory: true)
            .standardizedFileURL
        droppedImageDirectoryURL =
            rootURL
            .appendingPathComponent("Dropped Images", isDirectory: true)
        droppedFileDirectoryURL =
            rootURL
            .appendingPathComponent("Dropped Files", isDirectory: true)
        self.trashItem = trashItem
    }

    func droppedImageURL(filename: String) -> URL {
        droppedImageDirectoryURL.appendingPathComponent(filename)
    }

    func createPromisedFileDirectory() throws -> URL {
        let directoryURL =
            droppedFileDirectoryURL
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL
    }

    func beginReading(_ url: URL) -> ReadLease? {
        guard let ownedURL = ownedURL(for: url) else { return nil }
        stateLock.lock()
        readCounts[ownedURL, default: 0] += 1
        stateLock.unlock()
        return ReadLease(store: self, url: ownedURL)
    }

    func moveToTrash(_ urls: [URL]) {
        for url in urls {
            requestCleanup(of: url)
        }
    }

    func trashAbandonedMaterializations(createdBefore cutoff: Date = Date()) {
        cleanupQueue.addOperation { [weak self] in
            guard let self else { return }
            let candidates = self.abandonedMaterializationCandidates()
            for candidate in candidates where self.wasLastChanged(candidate, before: cutoff) {
                self.requestCleanup(of: candidate)
            }
        }
    }

    func waitForPendingOperations() {
        cleanupQueue.waitUntilAllOperationsAreFinished()
    }

    private static func defaultApplicationSupportURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    private func endReading(_ url: URL) {
        var shouldSchedule = false
        stateLock.lock()
        if let count = readCounts[url], count > 1 {
            readCounts[url] = count - 1
        } else {
            readCounts.removeValue(forKey: url)
            if pendingURLs.contains(url), scheduledURLs.insert(url).inserted {
                shouldSchedule = true
            }
        }
        stateLock.unlock()
        if shouldSchedule {
            scheduleCleanup(of: url)
        }
    }

    private func requestCleanup(of url: URL) {
        guard let ownedURL = ownedURL(for: url) else { return }

        var shouldSchedule = false
        stateLock.lock()
        pendingURLs.insert(ownedURL)
        if readCounts[ownedURL] == nil, scheduledURLs.insert(ownedURL).inserted {
            shouldSchedule = true
        }
        stateLock.unlock()

        if shouldSchedule {
            scheduleCleanup(of: ownedURL)
        }
    }

    private func scheduleCleanup(of url: URL) {
        cleanupQueue.addOperation { [weak self] in
            self?.performScheduledCleanup(of: url)
        }
    }

    private func performScheduledCleanup(of url: URL) {
        stateLock.lock()
        guard readCounts[url] == nil, pendingURLs.remove(url) != nil else {
            scheduledURLs.remove(url)
            stateLock.unlock()
            return
        }
        scheduledURLs.remove(url)
        stateLock.unlock()

        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try trashItem(url)
            try pruneEmptyPromisedFileDirectory(containing: url)
        } catch {
            logger.error(
                "Failed to clean up \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func abandonedMaterializationCandidates() -> [URL] {
        let manager = FileManager.default
        let imageURLs =
            (try? manager.contentsOfDirectory(
                at: droppedImageDirectoryURL,
                includingPropertiesForKeys: nil
            )) ?? []
        let promisedFileURLs =
            (try? manager.contentsOfDirectory(
                at: droppedFileDirectoryURL,
                includingPropertiesForKeys: nil
            )) ?? []
        return (imageURLs + promisedFileURLs).filter { ownedURL(for: $0) != nil }
    }

    private func wasLastChanged(_ url: URL, before cutoff: Date) -> Bool {
        guard
            let values = try? url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .creationDateKey,
            ])
        else { return false }
        let dates = [values.contentModificationDate, values.creationDate].compactMap { $0 }
        guard let lastChanged = dates.max() else { return false }
        return lastChanged < cutoff
    }

    private func ownedURL(for url: URL) -> URL? {
        let candidate = url.standardizedFileURL
        if candidate.deletingLastPathComponent() == droppedImageDirectoryURL,
            Self.hasOwnedImageFilename(candidate)
        {
            return candidate
        }

        let rootPath = droppedFileDirectoryURL.path
        let candidatePath = candidate.path
        guard candidatePath.hasPrefix(rootPath + "/") else { return nil }
        let relativePath = candidatePath.dropFirst(rootPath.count + 1)
        guard let firstComponent = relativePath.split(separator: "/").first,
            UUID(uuidString: String(firstComponent)) != nil
        else { return nil }
        return candidate
    }

    private static func hasOwnedImageFilename(_ url: URL) -> Bool {
        let stem = url.deletingPathExtension().lastPathComponent
        guard stem.count >= 36 else { return false }
        return UUID(uuidString: String(stem.suffix(36))) != nil
    }

    private func pruneEmptyPromisedFileDirectory(containing url: URL) throws {
        let rootPath = droppedFileDirectoryURL.path
        let candidatePath = url.standardizedFileURL.path
        guard candidatePath.hasPrefix(rootPath + "/") else { return }
        let relativePath = candidatePath.dropFirst(rootPath.count + 1)
        guard let firstComponent = relativePath.split(separator: "/").first else { return }
        let directoryURL =
            droppedFileDirectoryURL
            .appendingPathComponent(String(firstComponent), isDirectory: true)
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        let contents = try FileManager.default.contentsOfDirectory(atPath: directoryURL.path)
        if contents.isEmpty {
            try trashItem(directoryURL)
        }
    }
}
