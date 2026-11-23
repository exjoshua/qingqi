import AppKit
import SwiftUI

private func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
    func color(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                green: CGFloat((rgb >> 8) & 255) / 255,
                blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
    return Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? color(dark) : color(light)
    })
}

private enum Paint {
    static let surface = adaptive(0xFCFCF9, 0x242825)
    static let footer = adaptive(0xF2F3EE, 0x1E221F)
    static let text = adaptive(0x202A25, 0xF0F3ED)
    static let muted = adaptive(0x626C64, 0xA4AEA5)
    static let rule = adaptive(0xDADFD7, 0x424A44)
    static let selected = adaptive(0xE7F2EB, 0x2B4238)
    static let selectedRule = adaptive(0xC6DDD0, 0x415F50)
    static let hover = adaptive(0xF0F2ED, 0x303732)
    static let key = adaptive(0xF8F9F5, 0x333A34)
}

private extension Ink {
    var color: Color {
        switch self {
        case .jade: return adaptive(0x21634F, 0x9ED3B9)
        case .amber: return adaptive(0x87571D, 0xE5BD81)
        case .violet: return adaptive(0x6C568A, 0xC7B2E3)
        case .blue: return adaptive(0x376783, 0xA2CCE4)
        case .rose: return adaptive(0x94594C, 0xDFB1A4)
        case .neutral: return Paint.muted
        }
    }
}

private struct KeyCap: View {
    let text: String
    var body: some View {
        Text(verbatim: text).font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Paint.muted).padding(.horizontal, 4).frame(minWidth: 17, minHeight: 17)
            .background(RoundedRectangle(cornerRadius: 4).fill(Paint.key))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Paint.rule, lineWidth: 0.8))
    }
}

private struct SearchInput: NSViewRepresentable {
    @ObservedObject var model: LauncherModel

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: LauncherModel
        var focusRequest = -1
        init(_ model: LauncherModel) { self.model = model }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            model.edit(field.stringValue)
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField, let editor = field.currentEditor() as? NSTextView else { return }
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.isAutomaticTextReplacementEnabled = false
            editor.isContinuousSpellCheckingEnabled = false
            editor.isAutomaticSpellingCorrectionEnabled = false
            editor.isAutomaticTextCompletionEnabled = false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if textView.hasMarkedText() { return false }
            switch selector {
            case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.insertTab(_:)): model.move(1)
            case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.insertBacktab(_:)): model.move(-1)
            case #selector(NSResponder.insertNewline(_:)): model.perform(model.selectedEntry)
            case #selector(NSResponder.cancelOperation(_:)): model.back()
            default: return false
            }
            return true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.identifier = NSUserInterfaceItemIdentifier("launcher-search")
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        // A single-line cell discards line breaks on paste. Keep the original
        // text for codecs and let the delegate handle the Return key.
        field.usesSingleLineMode = false
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.lineBreakMode = .byClipping
        field.font = .systemFont(ofSize: 22, weight: .regular)
        field.textColor = .labelColor
        field.delegate = context.coordinator
        field.setAccessibilityLabel("搜索或输入命令")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.placeholderString = model.mode?.placeholder ?? "搜索应用、路径，或输入算式…"
        if field.stringValue != model.query {
            field.stringValue = model.query
            if let editor = field.currentEditor(), editor.string != model.query { editor.string = model.query }
        }
        if context.coordinator.focusRequest != model.focusRequest {
            context.coordinator.focusRequest = model.focusRequest
            DispatchQueue.main.async {
                guard let window = field.window, window.isKeyWindow else { return }
                window.makeFirstResponder(field)
                field.currentEditor()?.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
            }
        }
    }
}

private struct IconTile: View {
    let entry: Entry
    var body: some View {
        Group {
            if let url = entry.appIcon {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(entry.ink.color.opacity(0.12))
                    Image(systemName: entry.symbol).font(.system(size: 17, weight: .medium))
                        .foregroundStyle(entry.ink.color)
                }
            }
        }.frame(width: 33, height: 33).accessibilityHidden(true)
    }
}

private func preview(_ text: String) -> String {
    // Only the single-line preview is shortened. The action retains the original text.
    if text.isEmpty { return "（空文本）" }
    return String(text.prefix(220)).replacingOccurrences(of: "\r\n", with: " ↵ ")
        .replacingOccurrences(of: "\n", with: " ↵ ").replacingOccurrences(of: "\r", with: " ↵ ")
}

private struct ResultRow: View {
    let entry: Entry
    let selected: Bool
    let run: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: run) {
            HStack(spacing: 11) {
                IconTile(entry: entry)
                VStack(alignment: .leading, spacing: 2) {
                    if entry.isValue {
                        Text(verbatim: entry.detail).font(.system(size: 10, weight: .medium)).foregroundStyle(Paint.muted)
                        Text(verbatim: preview(entry.title)).font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundStyle(Paint.text)
                    } else {
                        Text(verbatim: preview(entry.title)).font(.system(size: 14, weight: .medium)).foregroundStyle(Paint.text)
                        Text(verbatim: entry.detail).font(.system(size: 11)).foregroundStyle(Paint.muted)
                    }
                }.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if !entry.badge.isEmpty {
                    Text(verbatim: entry.badge).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Paint.muted).padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Paint.rule, lineWidth: 0.8))
                } else if selected {
                    Image(systemName: entry.isValue ? "doc.on.doc" : "return")
                        .font(.system(size: 12)).foregroundStyle(Ink.jade.color).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 11).frame(height: 47)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Paint.selected : hovered ? Paint.hover : .clear))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Paint.selectedRule : .clear, lineWidth: 0.8))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).focusable(false).onHover { hovered = $0 }
        .accessibilityLabel(Text(verbatim: entry.detail + "，" + preview(entry.title)))
    }
}

private struct JumpChip: View {
    let entry: Entry
    let selected: Bool
    let run: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: run) {
            HStack(spacing: 8) {
                Image(systemName: entry.symbol).font(.system(size: 13)).foregroundStyle(Ink.jade.color)
                Text(verbatim: entry.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Paint.text)
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .medium)).foregroundStyle(Paint.muted)
            }.padding(.horizontal, 11).frame(height: 33)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Paint.selected : hovered ? Paint.hover : Paint.surface))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Paint.selectedRule : Paint.rule, lineWidth: 0.8))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).focusable(false).onHover { hovered = $0 }
    }
}

struct LauncherView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                if let tool = model.mode {
                    Button { model.show() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                            Text(tool.name).font(.system(size: 12, weight: .semibold))
                        }.foregroundStyle(tool.info.ink.color).padding(.horizontal, 10).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 7).fill(tool.info.ink.color.opacity(0.11)))
                    }.buttonStyle(.plain).focusable(false).help("返回主面板")
                } else {
                    Image(systemName: "magnifyingglass").font(.system(size: 23, weight: .medium))
                        .foregroundStyle(Ink.jade.color).accessibilityHidden(true)
                }
                SearchInput(model: model).frame(maxWidth: .infinity).frame(height: 29)
                Button { model.back() } label: { KeyCap(text: "esc") }
                    .buttonStyle(.plain).focusable(false).help("返回或关闭")
            }.padding(.horizontal, 23).frame(height: 71)
            Rectangle().fill(Paint.rule).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 11) {
                        ForEach(model.groups) { group in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(verbatim: group.title).font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Paint.muted).padding(.leading, 9)
                                if group.chips {
                                    HStack(spacing: 8) {
                                        ForEach(group.entries) { entry in
                                            JumpChip(entry: entry, selected: model.selected == entry.id) { model.perform(entry) }
                                                .id(entry.id)
                                        }
                                    }.padding(.horizontal, 4)
                                } else {
                                    LazyVStack(spacing: 1) {
                                        ForEach(group.entries) { entry in
                                            ResultRow(entry: entry, selected: model.selected == entry.id) { model.perform(entry) }
                                                .id(entry.id)
                                        }
                                    }
                                }
                            }
                        }
                        if let blank = model.empty {
                            VStack(spacing: 9) {
                                Image(systemName: blank.symbol).font(.system(size: 24, weight: .light))
                                    .foregroundStyle(Ink.jade.color).padding(.bottom, 2)
                                Text(verbatim: blank.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Paint.text)
                                if !blank.detail.isEmpty {
                                    Text(verbatim: blank.detail).font(.system(size: 12)).foregroundStyle(Paint.muted)
                                }
                            }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 21)
                        }
                        if let note = model.footnote {
                            Text(verbatim: note).font(.system(size: 11)).foregroundStyle(Paint.muted)
                                .padding(.horizontal, 10).textSelection(.enabled)
                        }
                    }.padding(.horizontal, 13).padding(.vertical, 12)
                }.onChange(of: model.selected) { id in if let id { proxy.scrollTo(id) } }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(Paint.rule).frame(height: 1)
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).fill(Color(red: 0.12, green: 0.32, blue: 0.25))
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Color(red: 0.76, green: 0.94, blue: 0.76))
                }.frame(width: 20, height: 20)
                Text("轻启").font(.system(size: 12, weight: .semibold)).foregroundStyle(Paint.text)
                if model.displayingClipboard && !model.history.items.isEmpty {
                    Button("清空历史") { model.clearHistory() }.buttonStyle(.plain).focusable(false)
                        .font(.system(size: 11)).foregroundStyle(Paint.muted).padding(.leading, 8)
                }
                Spacer()
                if let entry = model.selectedEntry {
                    KeyCap(text: "↑")
                    KeyCap(text: "↓")
                    Text("选择").padding(.trailing, 5)
                    Rectangle().fill(Paint.rule).frame(width: 1, height: 13).padding(.trailing, 3)
                    KeyCap(text: "↵")
                    Text(verbatim: entry.action.verb)
                }
            }.font(.system(size: 11)).foregroundStyle(Paint.muted)
                .padding(.horizontal, 21).frame(height: 39).background(Paint.footer)
        }
        .background(Paint.surface)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(Paint.rule, lineWidth: 1))
    }
}
