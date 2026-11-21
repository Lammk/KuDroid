import Foundation

struct MemoryBudgetConfiguration: Codable, Equatable {
    var enabled: Bool
    var percent: Int

    init(enabled: Bool, percent: Int) {
        self.percent = (0...100).contains(percent) ? percent : 70
        self.enabled = enabled && percent > 0 && percent < 100
    }
}

enum MemoryBudgetValidation: Equatable {
    case invalid, disabled(Int), recommended(Int), confirmation(Int)

    var percent: Int? {
        switch self {
        case .invalid: return nil
        case .disabled(let value), .recommended(let value), .confirmation(let value): return value
        }
    }

    static func parse(_ text: String) -> Self {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix("%") { value.removeLast() }
        guard let percent = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              (0...100).contains(percent) else { return .invalid }
        if percent == 0 || percent == 100 { return .disabled(percent) }
        if (40...95).contains(percent) { return .recommended(percent) }
        return .confirmation(percent)
    }
}

enum MemoryBudgetPolicy {
    static func bytes(available: UInt64, percent: Int) -> UInt64 {
        guard (1...100).contains(percent) else { return 0 }
        let value = UInt64(percent)
        return available / 100 * value + available % 100 * value / 100
    }

    static func recommendation(hardwareBytes: UInt64) -> String {
        guard hardwareBytes > 0 else { return "Memory will be measured when an app opens." }
        let gib = Int((Double(hardwareBytes) / 1_073_741_824).rounded())
        if gib < 6 {
            return "Recommended to reduce out-of-memory crashes. Performance may be lower."
        }
        return "Enable if you prefer stability over performance. Your device has \(gib) GB of RAM."
    }
}
