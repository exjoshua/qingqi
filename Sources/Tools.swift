import Foundation

struct ToolError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Calculator {
    private enum Op: String {
        case add = "+", subtract = "-", multiply = "*", divide = "/", power = "^"
        case negative, positive, leftParen

        var precedence: Int {
            switch self {
            case .leftParen: return 0
            case .add, .subtract: return 1
            case .multiply, .divide: return 2
            case .negative, .positive: return 3
            case .power: return 4
            }
        }
    }

    static func evaluate(_ expression: String) throws -> String {
        let ascii = expression
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
        let scanner = Scanner(string: ascii)
        scanner.locale = Locale(identifier: "en_US_POSIX")
        scanner.charactersToBeSkipped = nil
        var values: [Double] = []
        var operators: [Op] = []
        var expectsValue = true

        func apply(_ op: Op) throws {
            guard op != .leftParen else { throw ToolError("请补上右括号") }
            guard let right = values.popLast() else { throw ToolError("算式缺少数字") }
            if op == .negative || op == .positive {
                values.append(op == .negative ? -right : right)
                return
            }
            guard let left = values.popLast() else { throw ToolError("算式缺少数字") }
            let value: Double
            switch op {
            case .add: value = left + right
            case .subtract: value = left - right
            case .multiply: value = left * right
            case .divide:
                guard right != 0 else { throw ToolError("除数不能为零") }
                value = left / right
            case .power: value = pow(left, right)
            default: preconditionFailure("Expected a binary operator")
            }
            guard value.isFinite else { throw ToolError("结果超出可表示的实数范围") }
            values.append(value)
        }

        while !scanner.isAtEnd {
            if scanner.scanCharacters(from: .whitespacesAndNewlines) != nil { continue }
            if expectsValue {
                if scanner.scanString("(") != nil { operators.append(.leftParen); continue }
                if scanner.scanString("-") != nil { operators.append(.negative); continue }
                if scanner.scanString("+") != nil { operators.append(.positive); continue }
                guard let number = scanner.scanDouble(), number.isFinite else {
                    throw ToolError("这里需要数字或左括号")
                }
                values.append(number)
                expectsValue = false
                continue
            }
            if scanner.scanString("%") != nil {
                values[values.count - 1] /= 100
                continue
            }
            if scanner.scanString(")") != nil {
                while let op = operators.last, op != .leftParen {
                    operators.removeLast()
                    try apply(op)
                }
                guard operators.popLast() == .leftParen else { throw ToolError("多了一个右括号") }
                continue
            }
            let token = String(scanner.string[scanner.currentIndex])
            guard let next = Op(rawValue: token) else { throw ToolError("这里需要运算符") }
            scanner.currentIndex = scanner.string.index(after: scanner.currentIndex)
            while let top = operators.last, top.precedence > next.precedence ||
                    (top.precedence == next.precedence && next != .power) {
                operators.removeLast()
                try apply(top)
            }
            operators.append(next)
            expectsValue = true
        }
        guard !expectsValue else { throw ToolError("请补全算式") }
        while let op = operators.popLast() { try apply(op) }
        let result = values[0]
        if let integer = Int64(exactly: result) { return String(integer) }
        return String(format: "%.15g", result)
    }
}

enum TextCodec {
    // RFC 3986 §2.3. Encode one URL component, including its literal delimiters.
    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func base64Encode(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    static func base64Decode(_ text: String) throws -> String {
        let compact = text.components(separatedBy: .whitespacesAndNewlines).joined()
        guard let data = Data(base64Encoded: compact) else { throw ToolError("输入不是有效的标准 Base64") }
        guard let decoded = String(data: data, encoding: .utf8) else {
            throw ToolError("解码后是二进制数据，无法显示为 UTF-8 文本")
        }
        return decoded
    }

    static func urlEncode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved)!
    }

    static func urlDecode(_ text: String) throws -> String {
        guard let decoded = text.removingPercentEncoding else {
            throw ToolError("请检查百分号后的两位十六进制数字和 UTF-8 编码")
        }
        return decoded
    }
}

struct TimeValue {
    let label: String
    let value: String
}

struct TimeGroup {
    let title: String
    let values: [TimeValue]
}

final class TimeConverter {
    private let zone: TimeZone
    private let localDisplay: DateFormatter
    private let localFormats: [DateFormatter]
    private let iso: ISO8601DateFormatter
    private let isoFractional: ISO8601DateFormatter

    init(zone: TimeZone = .autoupdatingCurrent) {
        self.zone = zone
        func formatter(_ format: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = zone
            formatter.dateFormat = format
            formatter.isLenient = false
            return formatter
        }
        localDisplay = formatter("yyyy-MM-dd HH:mm:ss.SSS")
        localFormats = ["yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss",
                        "yyyy-MM-dd HH:mm", "yyyy-MM-dd"].map(formatter)
        iso = ISO8601DateFormatter()
        isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    private func dates(_ date: Date) -> [TimeValue] {
        var local = localDisplay.string(from: date)
        var utc = isoFractional.string(from: date)
        if local.hasSuffix(".000") { local.removeLast(4) }
        if utc.hasSuffix(".000Z") { utc = String(utc.dropLast(5)) + "Z" }
        return [TimeValue(label: "本地时间 · " + zone.identifier, value: local),
                TimeValue(label: "UTC · ISO 8601", value: utc)]
    }

    func convert(_ input: String, now: Date = Date()) throws -> [TimeGroup] {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let current = text.isEmpty || lower == "now" || text == "现在"
        if !current {
            let unit = lower.hasSuffix("ms") ? "ms" : lower.hasSuffix("s") ? "s" : ""
            let raw = lower.dropLast(unit.count).trimmingCharacters(in: .whitespaces)
            if let value = Double(raw), value.isFinite {
                // A bare integer can designate either unit. Keep both interpretations.
                let today = now.timeIntervalSince1970
                let preferMilliseconds = abs(value / 1000 - today) < abs(value - today)
                let preferred = preferMilliseconds ? ["ms", "s"] : ["s", "ms"]
                return (unit.isEmpty ? preferred : [unit]).map { interpretation in
                    let seconds = interpretation == "ms" ? value / 1000 : value
                    return TimeGroup(title: interpretation == "ms" ? "按毫秒解读" : "按秒解读",
                                     values: dates(Date(timeIntervalSince1970: seconds)))
                }
            }
        }

        let localText = text.replacingOccurrences(of: "T", with: " ")
        let parsed: Date?
        if current { parsed = now }
        else {
            parsed = isoFractional.date(from: text) ?? iso.date(from: text) ??
                localFormats.lazy.compactMap { $0.date(from: localText) }.first
        }
        guard let date = parsed else {
            throw ToolError("请输入 Unix 时间戳、ISO 8601 或本地日期时间")
        }
        let seconds = date.timeIntervalSince1970
        guard let whole = Int64(exactly: floor(seconds)),
              let millis = Int64(exactly: (seconds * 1000).rounded()) else {
            throw ToolError("超出 64 位 Unix 时间戳的范围")
        }
        let unix = TimeGroup(title: "Unix 时间戳", values: [
            TimeValue(label: "秒", value: String(whole)),
            TimeValue(label: "毫秒", value: String(millis))
        ])
        return [unix, TimeGroup(title: "日期时间", values: dates(date))]
    }
}
