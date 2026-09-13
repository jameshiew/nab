struct InboundDropFailure: Equatable, Sendable {
    let errorDescription: String
}

struct InboundDropResult: Equatable {
    let successfulEntries: [FileEntry]
    let failures: [InboundDropFailure]

    init(
        successfulEntries: [FileEntry],
        failures: [InboundDropFailure] = []
    ) {
        self.successfulEntries = successfulEntries
        self.failures = failures
    }

    var partialFailureMessage: String? {
        guard !successfulEntries.isEmpty, !failures.isEmpty else { return nil }
        let successfulCount = successfulEntries.count
        let totalCount = successfulCount + failures.count
        let verb = successfulCount == 1 ? "was" : "were"
        return
            "\(successfulCount) of \(totalCount) files \(verb) parked; \(failures.count) failed."
    }
}
