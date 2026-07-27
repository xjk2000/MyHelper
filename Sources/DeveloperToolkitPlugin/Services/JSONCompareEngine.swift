import Foundation

struct JSONComparisonResult {
    let leftSortedText: String
    let rightSortedText: String
    let summary: JSONComparisonSummary
    let rows: [JSONDiffLine]
    let pairedRows: [JSONDiffPairRow]
}

struct JSONComparisonSummary {
    let added: [JSONPathChange]
    let removed: [JSONPathChange]
    let changed: [JSONPathChange]

    var hasChanges: Bool {
        !added.isEmpty || !removed.isEmpty || !changed.isEmpty
    }
}

struct JSONPathChange: Identifiable, Hashable {
    let id: String
    let path: String
    let leftValue: String?
    let rightValue: String?
}

struct JSONDiffLine: Identifiable, Hashable {
    let id: Int
    let kind: JSONDiffLineKind
    let leftLineNumber: Int?
    let rightLineNumber: Int?
    let text: String
}

enum JSONDiffLineKind: Hashable {
    case unchanged
    case added
    case removed
}

struct JSONDiffPairRow: Identifiable, Hashable {
    let id: Int
    let marker: JSONDiffPairMarker
    let left: JSONDiffSideLine
    let right: JSONDiffSideLine
}

struct JSONDiffSideLine: Hashable {
    let lineNumber: Int?
    let text: String
    let kind: JSONDiffSideKind
}

enum JSONDiffSideKind: Hashable {
    case unchanged
    case removed
    case added
    case empty
}

enum JSONDiffPairMarker: Hashable {
    case unchanged
    case added
    case removed
    case changed
}

enum JSONCompareEngine {
    private static let maxExactDiffCells = 2_250_000

    static func compare(left: String, right: String, indent: Int) throws -> JSONComparisonResult {
        let leftObject = try parseJSON(left, side: "左侧")
        let rightObject = try parseJSON(right, side: "右侧")

        let leftSortedText = try serializeSorted(leftObject, pretty: true, indent: indent)
        let rightSortedText = try serializeSorted(rightObject, pretty: true, indent: indent)
        let summary = summary(leftObject: leftObject, rightObject: rightObject)
        let rows = diffLines(
            left: leftSortedText.components(separatedBy: .newlines),
            right: rightSortedText.components(separatedBy: .newlines)
        )

        return JSONComparisonResult(
            leftSortedText: leftSortedText,
            rightSortedText: rightSortedText,
            summary: summary,
            rows: rows,
            pairedRows: pairedRows(from: rows)
        )
    }

    static func sortedJSONString(_ input: String, indent: Int) throws -> String {
        try serializeSorted(parseJSON(input, side: "输入"), pretty: true, indent: indent)
    }

    private static func parseJSON(_ input: String, side: String) throws -> Any {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8), !data.isEmpty else {
            throw DeveloperToolError.invalidInput("\(side) JSON 为空")
        }
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw DeveloperToolError.invalidInput("\(side) JSON 解析失败：\(error.localizedDescription)")
        }
    }

    private static func serializeSorted(_ object: Any, pretty: Bool, indent: Int) throws -> String {
        var options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .sortedKeys]
        if pretty {
            options.insert(.prettyPrinted)
        }

        let data = try JSONSerialization.data(withJSONObject: object, options: options)
        guard var output = String(data: data, encoding: .utf8) else {
            throw DeveloperToolError.invalidInput("无法生成 UTF-8 JSON")
        }

        if pretty, indent == 4 {
            output = output
                .components(separatedBy: "\n")
                .map { line in
                    let leadingSpaces = line.prefix { $0 == " " }.count
                    return String(repeating: " ", count: leadingSpaces * 2) + line.dropFirst(leadingSpaces)
                }
                .joined(separator: "\n")
        }
        return output
    }

    private static func summary(leftObject: Any, rightObject: Any) -> JSONComparisonSummary {
        let leftValues = flattenedValues(leftObject, path: "$")
        let rightValues = flattenedValues(rightObject, path: "$")
        let leftKeys = Set(leftValues.keys)
        let rightKeys = Set(rightValues.keys)

        let removed = leftKeys.subtracting(rightKeys)
            .sorted()
            .map { path in
                JSONPathChange(id: "removed-\(path)", path: path, leftValue: leftValues[path], rightValue: nil)
            }
        let added = rightKeys.subtracting(leftKeys)
            .sorted()
            .map { path in
                JSONPathChange(id: "added-\(path)", path: path, leftValue: nil, rightValue: rightValues[path])
            }
        let changed = leftKeys.intersection(rightKeys)
            .filter { leftValues[$0] != rightValues[$0] }
            .sorted()
            .map { path in
                JSONPathChange(id: "changed-\(path)", path: path, leftValue: leftValues[path], rightValue: rightValues[path])
            }

        return JSONComparisonSummary(added: added, removed: removed, changed: changed)
    }

    private static func flattenedValues(_ value: Any, path: String) -> [String: String] {
        if let dictionary = value as? [String: Any] {
            guard !dictionary.isEmpty else {
                return [path: "{}"]
            }
            return dictionary.keys.sorted().reduce(into: [:]) { result, key in
                let childPath = pathForObjectKey(key, parentPath: path)
                result.merge(
                    flattenedValues(dictionary[key] ?? NSNull(), path: childPath),
                    uniquingKeysWith: { _, new in new }
                )
            }
        }

        if let array = value as? [Any] {
            guard !array.isEmpty else {
                return [path: "[]"]
            }
            return array.enumerated().reduce(into: [:]) { result, item in
                result.merge(
                    flattenedValues(item.element, path: "\(path)[\(item.offset)]"),
                    uniquingKeysWith: { _, new in new }
                )
            }
        }

        return [path: scalarDescription(value)]
    }

    private static func pathForObjectKey(_ key: String, parentPath: String) -> String {
        if key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil {
            return "\(parentPath).\(key)"
        }
        return "\(parentPath)[\"\(key.replacingOccurrences(of: "\"", with: "\\\""))\"]"
    }

    private static func scalarDescription(_ value: Any) -> String {
        if value is NSNull {
            return "null"
        }
        if let string = value as? String {
            return "\"\(string)\""
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        return String(describing: value)
    }

    private static func diffLines(left: [String], right: [String]) -> [JSONDiffLine] {
        if left.count * right.count > maxExactDiffCells {
            return fallbackDiffLines(left: left, right: right)
        }

        let width = right.count + 1
        var table = Array(repeating: 0, count: (left.count + 1) * (right.count + 1))

        if !left.isEmpty, !right.isEmpty {
            for leftIndex in stride(from: left.count - 1, through: 0, by: -1) {
                for rightIndex in stride(from: right.count - 1, through: 0, by: -1) {
                    let index = leftIndex * width + rightIndex
                    if left[leftIndex] == right[rightIndex] {
                        table[index] = table[(leftIndex + 1) * width + rightIndex + 1] + 1
                    } else {
                        table[index] = max(
                            table[(leftIndex + 1) * width + rightIndex],
                            table[leftIndex * width + rightIndex + 1]
                        )
                    }
                }
            }
        }

        var rows: [JSONDiffLine] = []
        var leftIndex = 0
        var rightIndex = 0
        var rowID = 0

        func append(_ kind: JSONDiffLineKind, leftLine: Int?, rightLine: Int?, text: String) {
            rows.append(
                JSONDiffLine(
                    id: rowID,
                    kind: kind,
                    leftLineNumber: leftLine,
                    rightLineNumber: rightLine,
                    text: text
                )
            )
            rowID += 1
        }

        while leftIndex < left.count || rightIndex < right.count {
            if leftIndex < left.count,
               rightIndex < right.count,
               left[leftIndex] == right[rightIndex] {
                append(.unchanged, leftLine: leftIndex + 1, rightLine: rightIndex + 1, text: left[leftIndex])
                leftIndex += 1
                rightIndex += 1
            } else if rightIndex < right.count,
                      (leftIndex == left.count || table[leftIndex * width + rightIndex + 1] >= table[(leftIndex + 1) * width + rightIndex]) {
                append(.added, leftLine: nil, rightLine: rightIndex + 1, text: right[rightIndex])
                rightIndex += 1
            } else if leftIndex < left.count {
                append(.removed, leftLine: leftIndex + 1, rightLine: nil, text: left[leftIndex])
                leftIndex += 1
            }
        }

        return rows
    }

    private static func fallbackDiffLines(left: [String], right: [String]) -> [JSONDiffLine] {
        let sharedCount = min(left.count, right.count)
        var rows: [JSONDiffLine] = []
        var rowID = 0

        func append(_ kind: JSONDiffLineKind, leftLine: Int?, rightLine: Int?, text: String) {
            rows.append(
                JSONDiffLine(
                    id: rowID,
                    kind: kind,
                    leftLineNumber: leftLine,
                    rightLineNumber: rightLine,
                    text: text
                )
            )
            rowID += 1
        }

        for index in 0..<sharedCount {
            if left[index] == right[index] {
                append(.unchanged, leftLine: index + 1, rightLine: index + 1, text: left[index])
            } else {
                append(.removed, leftLine: index + 1, rightLine: nil, text: left[index])
                append(.added, leftLine: nil, rightLine: index + 1, text: right[index])
            }
        }
        if left.count > sharedCount {
            for index in sharedCount..<left.count {
                append(.removed, leftLine: index + 1, rightLine: nil, text: left[index])
            }
        }
        if right.count > sharedCount {
            for index in sharedCount..<right.count {
                append(.added, leftLine: nil, rightLine: index + 1, text: right[index])
            }
        }
        return rows
    }

    private static func pairedRows(from rows: [JSONDiffLine]) -> [JSONDiffPairRow] {
        var result: [JSONDiffPairRow] = []
        var cursor = 0
        var pairID = 0

        func append(
            marker: JSONDiffPairMarker,
            left: JSONDiffSideLine,
            right: JSONDiffSideLine
        ) {
            result.append(
                JSONDiffPairRow(
                    id: pairID,
                    marker: marker,
                    left: left,
                    right: right
                )
            )
            pairID += 1
        }

        while cursor < rows.count {
            let row = rows[cursor]
            if row.kind == .unchanged {
                let side = JSONDiffSideLine(
                    lineNumber: row.leftLineNumber,
                    text: row.text,
                    kind: .unchanged
                )
                append(
                    marker: .unchanged,
                    left: side,
                    right: JSONDiffSideLine(
                        lineNumber: row.rightLineNumber,
                        text: row.text,
                        kind: .unchanged
                    )
                )
                cursor += 1
                continue
            }

            var removed: [JSONDiffLine] = []
            var added: [JSONDiffLine] = []
            while cursor < rows.count, rows[cursor].kind != .unchanged {
                switch rows[cursor].kind {
                case .removed:
                    removed.append(rows[cursor])
                case .added:
                    added.append(rows[cursor])
                case .unchanged:
                    break
                }
                cursor += 1
            }

            let count = max(removed.count, added.count)
            for index in 0..<count {
                let removedLine = index < removed.count ? removed[index] : nil
                let addedLine = index < added.count ? added[index] : nil
                let marker: JSONDiffPairMarker
                if removedLine != nil, addedLine != nil {
                    marker = .changed
                } else if addedLine != nil {
                    marker = .added
                } else {
                    marker = .removed
                }
                append(
                    marker: marker,
                    left: JSONDiffSideLine(
                        lineNumber: removedLine?.leftLineNumber,
                        text: removedLine?.text ?? "",
                        kind: removedLine == nil ? .empty : .removed
                    ),
                    right: JSONDiffSideLine(
                        lineNumber: addedLine?.rightLineNumber,
                        text: addedLine?.text ?? "",
                        kind: addedLine == nil ? .empty : .added
                    )
                )
            }
        }

        return result
    }
}
