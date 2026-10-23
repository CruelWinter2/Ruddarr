#if os(iOS)
import UIKit
import UniformTypeIdentifiers

// Presents UIDocumentPickerViewController from the top-most screen, so it works
// wherever the calling view sits (including inside the "More" tab).
@MainActor
final class DocumentPicker: NSObject, UIDocumentPickerDelegate {
    static let shared = DocumentPicker()

    private var completion: ((URL) -> Void)?

    func pick(_ types: [UTType], completion: @escaping (URL) -> Void) {
        guard let presenter = Self.topController() else { return }

        // asCopy hands back a file in the app's own inbox, so no security scope is needed
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        self.completion = completion
        presenter.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first { completion?(url) }
        completion = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion = nil
    }

    private static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
#endif
