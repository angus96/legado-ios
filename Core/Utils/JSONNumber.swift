import Foundation

enum JSONNumber {
    static func int64(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber {
            guard number.doubleValue.isFinite else { return nil }
            let decimal = number.decimalValue
            guard decimal >= Decimal(Int64.min), decimal <= Decimal(Int64.max) else { return nil }
            return number.int64Value
        }
        if let text = value as? String {
            return Int64(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func int32(_ value: Any?) -> Int32? {
        guard let number = int64(value) else { return nil }
        return Int32(exactly: number)
    }
}
