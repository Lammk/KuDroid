import Foundation
import UIKit
import Combine

final class AppIcons: ObservableObject {
    static let shared = AppIcons()
    @Published private(set) var revision = 0
    private var attempted: Set<String> = []
    private let worker = DispatchQueue(label: "apk.icons", qos: .utility)

    func repair(_ directory: URL) {
        guard attempted.insert(directory.path).inserted else { return }
        let archive = directory.appendingPathComponent("base.apk")
        let destination = directory.appendingPathComponent("app_icon.png")
        let locale = Locale.preferredLanguages.first ?? ""
        worker.async {
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("Icon-" + UUID().uuidString)
            defer { try? fm.removeItem(at: work) }
            do {
                let attributes = try fm.attributesOfItem(atPath: archive.path)
                var failure: UnsafeMutablePointer<CChar>?
                let result = kudroid_preview_apk(archive.path, work.path, locale, &failure)
                if let failure { free(failure) }
                guard result == 0 else { return }
                let image = work.appendingPathComponent("app_icon.png")
                guard let data = try? Data(contentsOf: image), UIImage(data: data) != nil else { return }
                let current = try fm.attributesOfItem(atPath: archive.path)
                guard NSDictionary(dictionary: attributes).isEqual(to: current),
                      !fm.fileExists(atPath: destination.path) else { return }
                try data.write(to: destination, options: .atomic)
                DispatchQueue.main.async { self.revision += 1 }
            } catch {
                return
            }
        }
    }
}
