import SwiftUI
import UIKit
import UniformTypeIdentifiers
import JITSupport

private struct DocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    let selected: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(selected: selected) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        KDPrepareDocumentAccess()
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let selected: ([URL]) -> Void
        private var finished = false
        init(selected: @escaping ([URL]) -> Void) { self.selected = selected }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finish(urls)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish([]) }
        private func finish(_ urls: [URL]) {
            guard !finished else { return }
            finished = true
            selected(urls)
        }
    }
}

enum ProviderDocument {
    static func copy(_ source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { available in
            do { try FileManager.default.copyItem(at: available, to: destination) }
            catch { copyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
    }
}

extension View {
    func documentPicker(isPresented: Binding<Bool>, types: [UTType],
                        completion: @escaping (Result<URL, Error>) -> Void) -> some View {
        sheet(isPresented: isPresented) {
            DocumentPicker(types: types) { urls in
                isPresented.wrappedValue = false
                guard let url = urls.first else { return }
                completion(.success(url))
            }.ignoresSafeArea()
        }
    }

    func apkPicker(isPresented: Binding<Bool>, completion: @escaping (Result<URL, Error>) -> Void) -> some View {
        documentPicker(isPresented: isPresented, types: APKFileTypes.supported) { result in
            completion(result.flatMap { url in
                APKFileTypes.accepts(url) ? .success(url) : .failure(ExportFailure("Choose an APK, XAPK, APKS, or APKM file."))
            })
        }
    }
}
