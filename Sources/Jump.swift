import AppKit

struct JumpTarget {
    let name: String
    let url: URL
    let symbol: String?
    let keywords: String

    static let places: [JumpTarget] = {
        let fm = FileManager.default
        let definitions: [(FileManager.SearchPathDirectory, String, String, String)] = [
            (.downloadsDirectory, "下载", "arrow.down.to.line", "downloads xiazai"),
            (.desktopDirectory, "桌面", "menubar.dock.rectangle", "desktop zhuomian"),
            (.applicationDirectory, "应用程序", "square.grid.2x2", "applications apps yingyong"),
            (.documentDirectory, "文稿", "doc.on.doc", "documents wengao"),
        ]
        var places = definitions.compactMap { directory, name, symbol, keywords -> JumpTarget? in
            let domain: FileManager.SearchPathDomainMask = directory == .applicationDirectory ? .localDomainMask : .userDomainMask
            guard let url = fm.urls(for: directory, in: domain).first else { return nil }
            return JumpTarget(name: name, url: url, symbol: symbol, keywords: keywords)
        }
        places.append(JumpTarget(name: "个人文件夹", url: fm.homeDirectoryForCurrentUser,
                                 symbol: "house", keywords: "home 主目录"))
        return places
    }()

    static func installedApps() -> [JumpTarget] {
        let fm = FileManager.default
        let roots = fm.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask, .systemDomainMask])
            + [URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true)]
        var urls: [URL] = []
        for root in roots {
            guard let iterator = fm.enumerator(at: root, includingPropertiesForKeys: [.isPackageKey],
                                                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in iterator where url.pathExtension.lowercased() == "app" {
                urls.append(url)
                iterator.skipDescendants()
            }
        }
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        if fm.fileExists(atPath: finder.path) { urls.append(finder) }
        var seen = Set<String>()
        return urls.compactMap { url -> JumpTarget? in
            guard seen.insert(url.resolvingSymlinksInPath().standardizedFileURL.path).inserted else { return nil }
            let display = fm.displayName(atPath: url.path)
            let name = display.lowercased().hasSuffix(".app") ? String(display.dropLast(4)) : display
            return JumpTarget(name: name, url: url, symbol: nil,
                              keywords: url.deletingPathExtension().lastPathComponent + (url == finder ? " 访达" : ""))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static let linkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func webURL(_ text: String) -> URL? {
        if let components = URLComponents(string: text),
           let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
           let host = components.host, !host.isEmpty {
            return components.url
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = linkDetector.firstMatch(in: text, range: range), match.range == range,
              let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    static func matchesPath(_ text: String) -> Bool {
        text == "~" || text.hasPrefix("~/") || text.hasPrefix("/") || text.hasPrefix("file://")
    }

    static func paths(_ input: String) throws -> [JumpTarget] {
        let fm = FileManager.default
        let path: String
        if input.hasPrefix("file://") {
            guard let url = URL(string: input), url.isFileURL else { throw ToolError("文件地址格式有误") }
            path = url.path
        } else {
            path = (input as NSString).expandingTildeInPath
        }
        let requested = URL(fileURLWithPath: path)
        func target(_ url: URL) -> JumpTarget {
            let directory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            return JumpTarget(name: fm.displayName(atPath: url.path), url: url,
                              symbol: directory ? "folder" : "doc", keywords: "")
        }
        let exists = fm.fileExists(atPath: path)
        var matches: [JumpTarget] = exists ? [target(requested)] : []
        if exists && !input.hasSuffix("/") { return matches }
        let parent = input.hasSuffix("/") ? requested : requested.deletingLastPathComponent()
        let fragment = input.hasSuffix("/") ? "" : requested.lastPathComponent
        if !fm.fileExists(atPath: parent.path) { return matches }
        let options: FileManager.DirectoryEnumerationOptions = fragment.hasPrefix(".") ? [] : [.skipsHiddenFiles]
        let children = try fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey], options: options)
        matches += children.filter { fragment.isEmpty || $0.lastPathComponent.localizedStandardContains(fragment) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map(target)
        return matches
    }

    static func search(_ text: String, in catalog: [JumpTarget]) -> [JumpTarget] {
        let query = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return catalog.compactMap { item -> (Int, JumpTarget)? in
            let names = [item.name, item.keywords].map {
                $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            }
            if names.contains(query) { return (0, item) }
            if names.contains(where: { $0.hasPrefix(query) }) { return (1, item) }
            if names.contains(where: { $0.contains(query) }) { return (2, item) }
            let initials = names.map { $0.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).compactMap(\.first) }
            if initials.contains(where: { String($0).hasPrefix(query) }) { return (3, item) }
            return nil
        }.sorted {
            $0.0 == $1.0 ? $0.1.name.localizedStandardCompare($1.1.name) == .orderedAscending : $0.0 < $1.0
        }.map { $0.1 }
    }
}
