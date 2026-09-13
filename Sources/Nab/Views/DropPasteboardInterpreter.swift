import AppKit
import UniformTypeIdentifiers

struct DropPasteboardInterpreter {
    typealias DiagnosticEvent = (_ name: String, _ details: [String: String]) -> Void

    enum Plan {
        case filePromise(NSFilePromiseReceiver)
        case fileURL(URL)
        case image(PendingImage)
    }

    struct PendingImage: Sendable {
        let data: Data
        let destinationURL: URL
    }

    static let supportedImageTypes: [(NSPasteboard.PasteboardType, String)] = [
        (NSPasteboard.PasteboardType(UTType.png.identifier), "png"),
        (NSPasteboard.PasteboardType(UTType.jpeg.identifier), "jpg"),
        (NSPasteboard.PasteboardType(UTType.heic.identifier), "heic"),
        (NSPasteboard.PasteboardType(UTType.tiff.identifier), "tiff"),
        (NSPasteboard.PasteboardType(UTType.gif.identifier), "gif"),
    ]

    let imageDestinationURL: (String) -> URL
    let recordDiagnosticEvent: DiagnosticEvent

    init(
        imageDestinationURL: @escaping (String) -> URL,
        recordDiagnosticEvent: @escaping DiagnosticEvent = { _, _ in }
    ) {
        self.imageDestinationURL = imageDestinationURL
        self.recordDiagnosticEvent = recordDiagnosticEvent
    }

    func plans(from pasteboard: NSPasteboard) -> [Plan] {
        let items = pasteboard.pasteboardItems ?? []
        let promiseReceivers =
            pasteboard.readObjects(
                forClasses: [NSFilePromiseReceiver.self],
                options: nil
            ) as? [NSFilePromiseReceiver] ?? []
        var promiseReceiverIndex = 0
        var plans: [Plan] = []
        for (index, item) in items.enumerated() {
            var itemWasPlanned = false
            let itemDetails = [
                "item_index": String(index),
                "types": item.types.map(\.rawValue).sorted().joined(separator: ","),
            ]
            recordDiagnosticEvent("drop_item_inspection_started", itemDetails)

            if Self.hasFilePromiseRepresentation(item),
                promiseReceivers.indices.contains(promiseReceiverIndex)
            {
                let receiver = promiseReceivers[promiseReceiverIndex]
                promiseReceiverIndex += 1
                recordDiagnosticEvent(
                    "drop_item_planned_as_file_promise",
                    itemDetails.merging([
                        "advertised_file_count": String(receiver.fileNames.count),
                        "advertised_type_count": String(receiver.fileTypes.count),
                    ]) { _, new in new }
                )
                plans.append(.filePromise(receiver))
                itemWasPlanned = true
                continue
            }
            recordDiagnosticEvent("drop_item_file_promise_absent", itemDetails)

            if let url = Self.fileURL(from: item) {
                recordDiagnosticEvent("drop_item_planned_as_file_url", itemDetails)
                plans.append(.fileURL(url))
                itemWasPlanned = true
                continue
            }
            recordDiagnosticEvent("drop_item_file_url_absent", itemDetails)

            for (type, ext) in Self.supportedImageTypes where item.types.contains(type) {
                recordDiagnosticEvent(
                    "drop_item_image_read_started",
                    itemDetails.merging(["image_type": type.rawValue]) { _, new in new }
                )
                guard let data = item.data(forType: type) else {
                    recordDiagnosticEvent(
                        "drop_item_image_read_returned_no_data",
                        itemDetails.merging(["image_type": type.rawValue]) { _, new in new }
                    )
                    continue
                }
                recordDiagnosticEvent(
                    "drop_item_planned_as_image",
                    itemDetails.merging([
                        "byte_count": String(data.count),
                        "image_type": type.rawValue,
                    ]) { _, new in new }
                )
                plans.append(
                    .image(
                        PendingImage(
                            data: data,
                            destinationURL: imageDestinationURL(ext)
                        )
                    )
                )
                itemWasPlanned = true
                break
            }
            if !itemWasPlanned {
                recordDiagnosticEvent("drop_item_unsupported", itemDetails)
            }
        }
        return plans
    }

    private static func hasFilePromiseRepresentation(_ item: NSPasteboardItem) -> Bool {
        let readableTypes = Set(
            NSFilePromiseReceiver.readableDraggedTypes.map {
                NSPasteboard.PasteboardType($0)
            }
        )
        return !readableTypes.isDisjoint(with: item.types)
    }

    private static func fileURL(from item: NSPasteboardItem) -> URL? {
        guard let value = item.string(forType: .fileURL),
            let url = URL(string: value),
            url.isFileURL,
            FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }
}
