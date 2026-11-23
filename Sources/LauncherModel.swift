import AppKit
import Combine

enum Ink { case jade, amber, violet, blue, rose, neutral }
enum Direction { case both, encode, decode }

enum Tool: String, CaseIterable {
    case clipboard, calculator, base64, url, timestamp

    var name: String {
        switch self {
        case .clipboard: return "剪贴板历史"
        case .calculator: return "计算器"
        case .base64: return "Base64 编解码"
        case .url: return "URL 编解码"
        case .timestamp: return "时间戳转换"
        }
    }

    var info: (symbol: String, ink: Ink, keyword: String, hint: String) {
        switch self {
        case .clipboard: return ("doc.on.clipboard", .jade, "clip", "搜索本次运行复制过的文本")
        case .calculator: return ("plus.forwardslash.minus", .amber, "=", "四则运算、乘方与百分比")
        case .base64: return ("chevron.left.forwardslash.chevron.right", .violet, "b64", "文本与 Base64 互转")
        case .url: return ("link", .blue, "url", "URL 组件的百分号编码与解码")
        case .timestamp: return ("clock.arrow.circlepath", .rose, "ts", "Unix 时间戳与日期时间互转")
        }
    }

    var placeholder: String {
        switch self {
        case .clipboard: return "搜索剪贴板历史…"
        case .calculator: return "输入算式，如 (48 + 12) × 1.25"
        case .base64: return "输入原文或 Base64…"
        case .url: return "输入原文或百分号编码…"
        case .timestamp: return "输入时间戳、日期或 now…"
        }
    }

    static func command(_ token: String) -> (Tool, Direction)? {
        switch token.lowercased() {
        case "clip", "clipboard": return (.clipboard, .both)
        case "calc", "=": return (.calculator, .both)
        case "b64", "base64": return (.base64, .both)
        case "b64e": return (.base64, .encode)
        case "b64d": return (.base64, .decode)
        case "url": return (.url, .both)
        case "urlencode": return (.url, .encode)
        case "urldecode": return (.url, .decode)
        case "ts", "time", "timestamp": return (.timestamp, .both)
        default: return nil
        }
    }
}

enum Action {
    case tool(Tool)
    case open(URL)
    case copy(String)
    case example(String)

    var verb: String {
        switch self {
        case .tool: return "进入工具"
        case .open: return "打开"
        case .copy: return "复制"
        case .example: return "试用示例"
        }
    }
}

struct Entry: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let ink: Ink
    let action: Action
    var badge: String = ""
    var isValue = false
    var appIcon: URL?
}

struct EntryGroup: Identifiable {
    let title: String
    let entries: [Entry]
    var chips = false
    var id: String { title }
}

struct EmptyState {
    let symbol: String
    let title: String
    let detail: String
}

final class LauncherModel: ObservableObject {
    let history: ClipboardHistory
    private let time = TimeConverter()
    private var apps: [JumpTarget] = []
    private var entries: [Entry] = []
    @Published private(set) var query = ""
    @Published private(set) var mode: Tool?
    @Published private(set) var groups: [EntryGroup] = []
    @Published private(set) var selected: String?
    @Published private(set) var empty: EmptyState?
    @Published private(set) var footnote: String?
    @Published private(set) var focusRequest = 0
    var openURL: ((URL) -> Void)?
    var didCopy: (() -> Void)?
    var dismiss: (() -> Void)?

    init(history: ClipboardHistory) {
        self.history = history
        refresh()
    }

    func loadApps() {
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = JumpTarget.installedApps()
            DispatchQueue.main.async {
                self.apps = apps
                self.refresh(keepSelection: true)
            }
        }
    }

    func show(_ tool: Tool? = nil) {
        mode = tool
        query = ""
        focusRequest += 1
        refresh()
    }

    func edit(_ newText: String) {
        guard newText != query else { return }
        query = newText
        refresh()
    }

    var selectedEntry: Entry? { entries.first { $0.id == selected } }

    func move(_ offset: Int) {
        guard !entries.isEmpty else { return }
        let index = selected.flatMap { id in entries.firstIndex { $0.id == id } } ?? 0
        selected = entries[min(max(0, index + offset), entries.count - 1)].id
    }

    func back() {
        if mode != nil || !query.isEmpty { show() }
        else { dismiss?() }
    }

    func perform(_ entry: Entry?) {
        guard let entry else { return }
        switch entry.action {
        case let .tool(tool): show(tool)
        case let .open(url): openURL?(url)
        case let .copy(text):
            do { try history.copy(text); didCopy?() }
            catch { report(error) }
        case let .example(text):
            if mode == nil { edit(query + text) }
            else { edit(text) }
            focusRequest += 1
        }
    }

    func report(_ error: Error) { footnote = error.localizedDescription }

    private typealias Command = (tool: Tool, direction: Direction, payload: String)
    private var command: Command? {
        if let mode { return (mode, .both, query) }
        if query.hasPrefix("=") { return (.calculator, .both, String(query.dropFirst())) }
        guard let split = query.firstIndex(where: \.isWhitespace),
              let (tool, direction) = Tool.command(String(query[..<split])) else { return nil }
        return (tool, direction, String(query[query.index(after: split)...]))
    }

    var displayingClipboard: Bool { command?.tool == .clipboard }

    func tick(clipboardChanged: Bool) {
        guard let command else { return }
        if command.tool == .clipboard && clipboardChanged { refresh(keepSelection: true) }
        if command.tool == .timestamp,
           ["", "now", "现在"].contains(command.payload.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            refresh(keepSelection: true)
        }
    }

    func clearHistory() {
        history.clear()
        refresh()
    }

    private func refresh(keepSelection: Bool = false) {
        let oldSelection = keepSelection ? selected : nil
        footnote = nil
        empty = nil
        do {
            if let command { groups = try toolGroups(command) }
            else { groups = try search() }
        } catch {
            groups = []
            empty = EmptyState(symbol: "text.magnifyingglass", title: error.localizedDescription,
                               detail: command?.tool == .timestamp ? "例如 1700000000s 或 2024-01-01 12:00:00" : "")
        }
        entries = groups.flatMap(\.entries)
        selected = oldSelection.flatMap { id in entries.contains { $0.id == id } ? id : nil } ?? entries.first?.id
    }

    private func toolEntry(_ tool: Tool) -> Entry {
        Entry(id: "tool-" + tool.rawValue, title: tool.name, detail: tool.info.hint,
              symbol: tool.info.symbol, ink: tool.info.ink, action: .tool(tool), badge: tool.info.keyword)
    }

    private func jumpEntry(_ target: JumpTarget) -> Entry {
        Entry(id: target.url.absoluteString, title: target.name,
              detail: (target.url.path as NSString).abbreviatingWithTildeInPath,
              symbol: target.symbol ?? "app", ink: .blue, action: .open(target.url),
              appIcon: target.symbol == nil ? target.url : nil)
    }

    private func search() throws -> [EntryGroup] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return [EntryGroup(title: "常用工具", entries: Tool.allCases.map(toolEntry)),
                    EntryGroup(title: "快速跳转", entries: JumpTarget.places.prefix(3).map(jumpEntry), chips: true)]
        }
        if JumpTarget.matchesPath(text) {
            let paths = try JumpTarget.paths(text).map(jumpEntry)
            if paths.isEmpty { empty = EmptyState(symbol: "folder", title: "没有匹配的路径", detail: "可输入绝对路径或以 ~/ 开头的路径。") }
            return paths.isEmpty ? [] : [EntryGroup(title: "本地路径", entries: paths)]
        }
        let isDate = text.range(of: #"^\d{4}-\d{2}-\d{2}(?:$|[T ])"#, options: .regularExpression) != nil
        if isDate || Int64(text) != nil {
            return try toolGroups((.timestamp, .both, text))
        }
        if text.range(of: #"^[-+0-9.(（−][0-9eE+*/^()%×÷−（）.\s-]*$"#, options: .regularExpression) != nil {
            return try toolGroups((.calculator, .both, text))
        }
        var found: [EntryGroup] = []
        if let web = JumpTarget.webURL(text) {
            found.append(EntryGroup(title: "网址", entries: [
                Entry(id: web.absoluteString, title: web.host ?? text, detail: web.absoluteString,
                      symbol: "globe", ink: .blue, action: .open(web))
            ]))
        }
        let exact = Tool.command(text)?.0
        let tools = Tool.allCases.filter {
            $0 == exact || $0.name.localizedStandardContains(text) || $0.info.keyword.localizedStandardContains(text)
        }.map(toolEntry)
        if !tools.isEmpty { found.append(EntryGroup(title: "工具", entries: tools)) }
        let jumps = JumpTarget.search(text, in: JumpTarget.places + apps).map(jumpEntry)
        if !jumps.isEmpty { found.append(EntryGroup(title: "快速跳转", entries: jumps)) }
        if found.isEmpty {
            empty = EmptyState(symbol: "magnifyingglass", title: "没有匹配的结果", detail: "试试应用名称、网址、绝对路径或 ~/ 开头的路径。")
        }
        return found
    }

    private func toolGroups(_ command: Command) throws -> [EntryGroup] {
        let (tool, direction, input) = command
        func output(_ id: String, _ label: String, _ text: String) -> Entry {
            Entry(id: id, title: text, detail: label, symbol: tool.info.symbol,
                  ink: tool.info.ink, action: .copy(text), isValue: true)
        }
        if tool == .clipboard {
            let clips = history.items.filter { input.isEmpty || $0.text.localizedStandardContains(input) }
            if history.accessDenied { footnote = "系统已拒绝读取剪贴板，可在「系统设置」中调整轻启的粘贴权限。" }
            if clips.isEmpty {
                empty = EmptyState(symbol: "doc.on.clipboard", title: input.isEmpty ? "还没有复制记录" : "没有匹配的文本",
                                   detail: input.isEmpty ? "启动后复制的文本会出现在这里，退出轻启后清空。" : "试试文本中的其他词。")
                return []
            }
            return [EntryGroup(title: "剪贴板历史", entries: clips.map { clip in
                Entry(id: clip.id.uuidString, title: clip.text, detail: clip.date.formatted(date: .abbreviated, time: .shortened),
                      symbol: "text.alignleft", ink: .jade, action: .copy(clip.text))
            })]
        }
        if tool == .timestamp {
            return try time.convert(input).map { group in
                EntryGroup(title: group.title, entries: group.values.map { value in
                    output(group.title + value.label, value.label, value.value)
                })
            }
        }
        if input.isEmpty {
            let sample: String
            switch tool {
            case .calculator: sample = "(48 + 12) × 1.25"
            case .base64: sample = direction == .decode ? "5L2g5aW9" : "你好，Mac"
            default: sample = direction == .decode ? "%E4%BD%A0%E5%A5%BD" : "轻启 / hello?"
            }
            return [EntryGroup(title: "试用示例", entries: [
                Entry(id: "example", title: sample, detail: tool.info.hint, symbol: tool.info.symbol,
                      ink: tool.info.ink, action: .example(sample))
            ])]
        }
        if tool == .calculator {
            return [EntryGroup(title: "计算结果", entries: [try output("result", "结果", Calculator.evaluate(input))])]
        }
        let isBase64 = tool == .base64
        var results: [Entry] = []
        if direction != .decode {
            let encoded = isBase64 ? TextCodec.base64Encode(input) : TextCodec.urlEncode(input)
            results.append(output("encode", "编码", encoded))
        }
        if direction != .encode {
            do {
                let decoded = try isBase64 ? TextCodec.base64Decode(input) : TextCodec.urlDecode(input)
                results.append(output("decode", "解码 · UTF-8", decoded))
            } catch {
                if direction == .decode { throw error }
                footnote = error.localizedDescription
            }
        }
        return [EntryGroup(title: tool.name, entries: results)]
    }
}
