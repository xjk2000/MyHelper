import Foundation

enum LinkHeader {
    /// 解析 RFC 5988 风格 Link header,返回 rel="next" 的 URL。
    /// 用正则匹配 <url> 后跟带 rel="next" 的参数,正确处理 URL 中含逗号的场景。
    static func nextURL(from header: String?) -> URL? {
        guard let header, !header.isEmpty else { return nil }
        // 匹配 <URL>; ... rel="next" 的整个 link-value(直到下一个 link-value 起点 < 或字符串末尾)
        let pattern = #"<([^>]+)>([^<]*?rel="next")"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let ns = header as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: header, options: [], range: range),
              match.numberOfRanges >= 2 else { return nil }
        let urlString = ns.substring(with: match.range(at: 1))
        return URL(string: urlString)
    }
}
