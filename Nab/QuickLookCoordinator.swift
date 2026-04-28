import AppKit
import QuickLookUI

@MainActor
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookCoordinator()
    private var urls: [URL] = []

    func preview(url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible, urls.first == url {
            panel.orderOut(nil)
            return
        }
        urls = [url]
        panel.dataSource = self
        panel.delegate = self
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard urls.indices.contains(index) else { return nil }
        return urls[index] as NSURL
    }

    func previewPanelWillClose(_ panel: QLPreviewPanel!) {
        urls = []
        panel.dataSource = nil
        panel.delegate = nil
    }
}
