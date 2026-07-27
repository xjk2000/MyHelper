import AppKit
import SwiftUI

struct JSONHighlightedTextView: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let onTextChange: (String) -> Void
    let onPasteTextChange: (String) -> Void

    init(
        text: Binding<String>,
        isEditable: Bool = true,
        onTextChange: @escaping (String) -> Void = { _ in },
        onPasteTextChange: @escaping (String) -> Void = { _ in }
    ) {
        _text = text
        self.isEditable = isEditable
        self.onTextChange = onTextChange
        self.onPasteTextChange = onPasteTextChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> JSONCodeEditorContainer {
        let container = JSONCodeEditorContainer(coordinator: context.coordinator)
        context.coordinator.install(container: container, fullText: text)
        container.textView.isEditable = isEditable
        return container
    }

    func updateNSView(_ container: JSONCodeEditorContainer, context: Context) {
        context.coordinator.parent = self
        container.textView.isEditable = isEditable
        guard context.coordinator.fullText != text else {
            context.coordinator.refreshTypingAttributes(on: container.textView)
            container.gutterView.needsDisplay = true
            return
        }
        context.coordinator.setFullText(text, in: container, preserveSelection: true)
    }

    final class Coordinator: NSObject, NSTextViewDelegate, JSONCodeTextViewDelegate, JSONGutterViewDelegate {
        var parent: JSONHighlightedTextView
        fileprivate var fullText = ""
        fileprivate var displayModel = JSONDisplayModel(fullText: "", collapsedIDs: [])

        private weak var container: JSONCodeEditorContainer?
        private var collapsedIDs: Set<String> = []
        private var isApplyingHighlight = false
        private var isUpdatingText = false

        init(_ parent: JSONHighlightedTextView) {
            self.parent = parent
        }

        fileprivate func install(container: JSONCodeEditorContainer, fullText: String) {
            self.container = container
            setFullText(fullText, in: container, preserveSelection: false)
        }

        fileprivate func setFullText(_ text: String, in container: JSONCodeEditorContainer, preserveSelection: Bool) {
            fullText = text
            rebuildDisplayModel()
            let sourceSelections = preserveSelection
                ? sourceRanges(fromDisplayRanges: container.textView.selectedRanges)
                : [NSValue(range: NSRange(location: 0, length: 0))]

            isUpdatingText = true
            container.textView.string = displayModel.displayText
            isUpdatingText = false

            applyHighlighting(to: container.textView)
            container.textView.selectedRanges = displayRanges(fromSourceRanges: sourceSelections)
            container.updateDocumentLayout()
            container.scrollToLeftPreservingVerticalPosition()
            container.gutterView.needsDisplay = true
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingHighlight,
                  !isUpdatingText,
                  let textView = notification.object as? JSONCodeTextView else {
                return
            }

            fullText = textView.string
            collapsedIDs.removeAll()
            rebuildDisplayModel()
            parent.text = fullText
            parent.onTextChange(fullText)

            let selectedRanges = textView.selectedRanges
            applyHighlighting(to: textView)
            textView.selectedRanges = JSONHighlightedTextView.clampedRanges(
                selectedRanges,
                textLength: (textView.string as NSString).length
            )
            container?.updateDocumentLayout()
            container?.gutterView.needsDisplay = true
        }

        func prepareForEditing(_ textView: JSONCodeTextView) {
            guard !collapsedIDs.isEmpty, let container else { return }
            let sourceSelections = sourceRanges(fromDisplayRanges: textView.selectedRanges)
            collapsedIDs.removeAll()
            rebuildDisplayModel()

            isUpdatingText = true
            textView.string = fullText
            isUpdatingText = false

            applyHighlighting(to: textView)
            textView.selectedRanges = displayRanges(fromSourceRanges: sourceSelections)
            container.updateDocumentLayout()
            container.gutterView.needsDisplay = true
        }

        func didPaste(in textView: JSONCodeTextView) {
            fullText = textView.string
            collapsedIDs.removeAll()
            rebuildDisplayModel()
            parent.text = fullText
            parent.onPasteTextChange(fullText)
        }

        func copySourceSelection(from textView: JSONCodeTextView) -> Bool {
            let selectedRanges = textView.selectedRanges.map(\.rangeValue)
            guard selectedRanges.contains(where: { $0.length > 0 }) else { return false }
            let source = fullText as NSString
            let copied = selectedRanges
                .map { displayRange -> String in
                    let sourceRange = sourceRange(fromDisplayRange: displayRange)
                    guard sourceRange.length > 0,
                          NSMaxRange(sourceRange) <= source.length else {
                        return ""
                    }
                    return source.substring(with: sourceRange)
                }
                .joined(separator: "\n")

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copied, forType: .string)
            return true
        }

        func toggleFold(atDisplayLine line: Int) {
            guard let marker = displayModel.markerByDisplayLine[line],
                  let container else { return }

            if collapsedIDs.contains(marker.id) {
                collapsedIDs.remove(marker.id)
            } else {
                collapsedIDs.insert(marker.id)
            }
            rebuildDisplayModel()

            let sourceSelections = sourceRanges(fromDisplayRanges: container.textView.selectedRanges)
            isUpdatingText = true
            container.textView.string = displayModel.displayText
            isUpdatingText = false

            applyHighlighting(to: container.textView)
            container.textView.selectedRanges = displayRanges(fromSourceRanges: sourceSelections)
            container.updateDocumentLayout()
            container.gutterView.needsDisplay = true
        }

        func visibleLineEntries(for gutterView: JSONGutterView) -> [JSONGutterLineEntry] {
            guard let container,
                  let layoutManager = container.textView.layoutManager,
                  let textContainer = container.textView.textContainer else {
                return []
            }

            layoutManager.ensureLayout(for: textContainer)
            if container.textView.string.isEmpty {
                return [
                    JSONGutterLineEntry(
                        displayLine: 0,
                        y: container.textView.textContainerInset.height,
                        marker: nil
                    )
                ]
            }

            let visibleRect = container.textView.visibleRect
            let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
            var glyphIndex = glyphRange.location
            let glyphLimit = NSMaxRange(glyphRange)
            var entries: [JSONGutterLineEntry] = []

            while glyphIndex < glyphLimit {
                var effectiveRange = NSRange(location: 0, length: 0)
                let lineRect = layoutManager.lineFragmentRect(
                    forGlyphAt: glyphIndex,
                    effectiveRange: &effectiveRange
                )
                let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
                let line = displayModel.lineNumber(atDisplayLocation: charIndex)
                let y = lineRect.minY + container.textView.textContainerOrigin.y - visibleRect.minY
                entries.append(
                    JSONGutterLineEntry(
                        displayLine: line,
                        y: y,
                        marker: displayModel.markerByDisplayLine[line]
                    )
                )
                glyphIndex = max(NSMaxRange(effectiveRange), glyphIndex + 1)
            }

            return entries
        }

        func displayLine(at point: NSPoint, in gutterView: JSONGutterView) -> Int? {
            guard let container,
                  let layoutManager = container.textView.layoutManager,
                  let textContainer = container.textView.textContainer else {
                return nil
            }

            var textPoint = NSPoint(
                x: container.textView.textContainerOrigin.x,
                y: point.y + container.textView.visibleRect.minY - container.textView.textContainerOrigin.y
            )
            textPoint.x = max(textPoint.x, 0)
            let glyphIndex = layoutManager.glyphIndex(for: textPoint, in: textContainer)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            return displayModel.lineNumber(atDisplayLocation: charIndex)
        }

        func refreshTypingAttributes(on textView: NSTextView) {
            textView.typingAttributes = JSONHighlightedTextView.baseAttributes
        }

        private func applyHighlighting(to textView: NSTextView) {
            isApplyingHighlight = true
            defer { isApplyingHighlight = false }

            let selectedRanges = textView.selectedRanges
            JSONHighlightedTextView.applyHighlighting(to: textView)
            textView.selectedRanges = JSONHighlightedTextView.clampedRanges(
                selectedRanges,
                textLength: (textView.string as NSString).length
            )
            refreshTypingAttributes(on: textView)
        }

        private func rebuildDisplayModel() {
            displayModel = JSONDisplayModel(fullText: fullText, collapsedIDs: collapsedIDs)
            collapsedIDs = collapsedIDs.intersection(Set(displayModel.regions.map(\.id)))
        }

        private func sourceRanges(fromDisplayRanges ranges: [NSValue]) -> [NSValue] {
            ranges.map { value in
                NSValue(range: sourceRange(fromDisplayRange: value.rangeValue))
            }
        }

        private func sourceRange(fromDisplayRange range: NSRange) -> NSRange {
            let start = displayModel.sourceLocation(forDisplayLocation: range.location)
            let end = displayModel.sourceLocation(forDisplayLocation: range.location + range.length)
            return NSRange(location: start, length: max(0, end - start))
        }

        private func displayRanges(fromSourceRanges ranges: [NSValue]) -> [NSValue] {
            ranges.map { value in
                let range = value.rangeValue
                let start = displayModel.displayLocation(forSourceLocation: range.location)
                let end = displayModel.displayLocation(forSourceLocation: range.location + range.length)
                return NSValue(range: NSRange(location: start, length: max(0, end - start)))
            }
        }
    }

    fileprivate static var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        return [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
    }

    private static func applyHighlighting(to textView: NSTextView) {
        let text = textView.string
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        guard let textStorage = textView.textStorage else { return }

        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes, range: fullRange)
        for token in JSONLexer.tokens(in: text) {
            textStorage.addAttribute(
                .foregroundColor,
                value: token.kind.color,
                range: token.range
            )
            if token.kind == .key {
                textStorage.addAttribute(
                    .font,
                    value: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                    range: token.range
                )
            }
        }
        textStorage.endEditing()
    }

    private static func clampedRanges(_ ranges: [NSValue], textLength: Int) -> [NSValue] {
        ranges.map { value in
            let range = value.rangeValue
            let location = min(max(range.location, 0), textLength)
            let length = min(max(range.length, 0), max(textLength - location, 0))
            return NSValue(range: NSRange(location: location, length: length))
        }
    }
}

final class JSONCodeEditorContainer: NSView {
    let gutterView: JSONGutterView
    let scrollView = NSScrollView()
    let textView = JSONCodeTextView()

    private let gutterWidth: CGFloat = 58
    private var boundsObserver: NSObjectProtocol?

    init(coordinator: JSONHighlightedTextView.Coordinator) {
        gutterView = JSONGutterView(delegate: coordinator)
        super.init(frame: .zero)
        setup(coordinator: coordinator)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    override func layout() {
        super.layout()
        gutterView.frame = NSRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
        scrollView.frame = NSRect(x: gutterWidth, y: 0, width: max(0, bounds.width - gutterWidth), height: bounds.height)
        updateDocumentLayout()
    }

    func scrollToLeftPreservingVerticalPosition() {
        let currentY = scrollView.contentView.bounds.origin.y
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: currentY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        gutterView.needsDisplay = true
    }

    func updateDocumentLayout() {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let contentSize = scrollView.contentSize
        let targetSize = NSSize(
            width: max(contentSize.width, ceil(usedRect.width + textView.textContainerInset.width * 2 + 24)),
            height: max(contentSize.height, ceil(usedRect.height + textView.textContainerInset.height * 2 + 24))
        )

        if abs(textView.frame.width - targetSize.width) > 0.5 ||
            abs(textView.frame.height - targetSize.height) > 0.5 {
            textView.setFrameSize(targetSize)
        }
        gutterView.needsDisplay = true
    }

    private func setup(coordinator: JSONHighlightedTextView.Coordinator) {
        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

        gutterView.autoresizingMask = [.height]
        addSubview(gutterView)

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.borderType = .noBorder
        scrollView.contentView.postsBoundsChangedNotifications = true

        textView.codeDelegate = coordinator
        textView.delegate = coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.enabledTextCheckingTypes = 0
        textView.typingAttributes = JSONHighlightedTextView.baseAttributes
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0

        scrollView.documentView = textView
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        addSubview(scrollView)

        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.gutterView.needsDisplay = true
        }
    }
}

protocol JSONCodeTextViewDelegate: AnyObject {
    func prepareForEditing(_ textView: JSONCodeTextView)
    func didPaste(in textView: JSONCodeTextView)
    func copySourceSelection(from textView: JSONCodeTextView) -> Bool
}

final class JSONCodeTextView: NSTextView {
    weak var codeDelegate: JSONCodeTextViewDelegate?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control),
           event.charactersIgnoringModifiers?.lowercased() == "v",
           isEditable {
            paste(nil)
            return
        }

        codeDelegate?.prepareForEditing(self)
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        codeDelegate?.prepareForEditing(self)
        super.paste(sender)
        codeDelegate?.didPaste(in: self)
    }

    override func cut(_ sender: Any?) {
        codeDelegate?.prepareForEditing(self)
        super.cut(sender)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        codeDelegate?.prepareForEditing(self)
        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func copy(_ sender: Any?) {
        if codeDelegate?.copySourceSelection(from: self) == true {
            return
        }
        super.copy(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "a":
            selectAll(nil)
            return true
        case "c":
            copy(nil)
            return true
        case "x":
            if isEditable {
                codeDelegate?.prepareForEditing(self)
                cut(nil)
                return true
            }
        case "v":
            if isEditable {
                paste(nil)
                return true
            }
        case "z":
            if flags.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            return true
        default:
            break
        }

        return super.performKeyEquivalent(with: event)
    }
}

struct JSONGutterLineEntry {
    let displayLine: Int
    let y: CGFloat
    let marker: JSONFoldMarker?
}

protocol JSONGutterViewDelegate: AnyObject {
    func visibleLineEntries(for gutterView: JSONGutterView) -> [JSONGutterLineEntry]
    func displayLine(at point: NSPoint, in gutterView: JSONGutterView) -> Int?
    func toggleFold(atDisplayLine line: Int)
}

final class JSONGutterView: NSView {
    weak var delegate: JSONGutterViewDelegate?
    private let markerWidth: CGFloat = 18

    override var isFlipped: Bool { true }

    init(delegate: JSONGutterViewDelegate) {
        self.delegate = delegate
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]

        for entry in delegate?.visibleLineEntries(for: self) ?? [] {
            if let marker = entry.marker {
                drawMarker(marker, y: entry.y)
            }
            let number = "\(entry.displayLine + 1)" as NSString
            number.draw(
                in: NSRect(x: markerWidth, y: entry.y + 1, width: bounds.width - markerWidth - 6, height: 16),
                withAttributes: attrs
            )
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard point.x <= markerWidth + 4,
              let line = delegate?.displayLine(at: point, in: self) else {
            return
        }
        delegate?.toggleFold(atDisplayLine: line)
    }

    private func drawMarker(_ marker: JSONFoldMarker, y: CGFloat) {
        let path = NSBezierPath()
        if marker.isCollapsed {
            path.move(to: NSPoint(x: 7, y: y + 4))
            path.line(to: NSPoint(x: 7, y: y + 14))
            path.line(to: NSPoint(x: 13, y: y + 9))
        } else {
            path.move(to: NSPoint(x: 4, y: y + 6))
            path.line(to: NSPoint(x: 14, y: y + 6))
            path.line(to: NSPoint(x: 9, y: y + 13))
        }
        path.close()
        NSColor.secondaryLabelColor.setFill()
        path.fill()
    }
}

struct JSONFoldRegion: Hashable {
    let id: String
    let range: NSRange
    let open: Character
    let close: Character
    let startLine: Int
    let endLine: Int

    var placeholder: String {
        "\(open)...\(close)"
    }
}

struct JSONFoldMarker {
    let id: String
    let isCollapsed: Bool
}

struct JSONDisplaySegment {
    let displayRange: NSRange
    let sourceRange: NSRange
    let isFolded: Bool
}

struct JSONDisplayModel {
    let fullText: String
    let displayText: String
    let regions: [JSONFoldRegion]
    let segments: [JSONDisplaySegment]
    let lineStarts: [Int]
    let markerByDisplayLine: [Int: JSONFoldMarker]

    init(fullText: String, collapsedIDs: Set<String>) {
        self.fullText = fullText
        let sourceLineStarts = Self.lineStarts(in: fullText)
        let parsedRegions = Self.parseFoldRegions(in: fullText, lineStarts: sourceLineStarts)
        let activeCollapsed = Self.topLevelCollapsedRegions(
            parsedRegions.filter { collapsedIDs.contains($0.id) }
        )

        var display = ""
        var builtSegments: [JSONDisplaySegment] = []
        let source = fullText as NSString
        var sourceCursor = 0

        func appendSegment(sourceRange: NSRange, text: String, folded: Bool) {
            guard sourceRange.length > 0 || !text.isEmpty else { return }
            let displayLocation = (display as NSString).length
            display += text
            builtSegments.append(
                JSONDisplaySegment(
                    displayRange: NSRange(location: displayLocation, length: (text as NSString).length),
                    sourceRange: sourceRange,
                    isFolded: folded
                )
            )
        }

        for region in activeCollapsed {
            if region.range.location > sourceCursor {
                let range = NSRange(location: sourceCursor, length: region.range.location - sourceCursor)
                appendSegment(sourceRange: range, text: source.substring(with: range), folded: false)
            }
            appendSegment(sourceRange: region.range, text: region.placeholder, folded: true)
            sourceCursor = NSMaxRange(region.range)
        }

        if sourceCursor < source.length {
            let range = NSRange(location: sourceCursor, length: source.length - sourceCursor)
            appendSegment(sourceRange: range, text: source.substring(with: range), folded: false)
        }

        if builtSegments.isEmpty {
            let length = (fullText as NSString).length
            builtSegments = [
                JSONDisplaySegment(
                    displayRange: NSRange(location: 0, length: length),
                    sourceRange: NSRange(location: 0, length: length),
                    isFolded: false
                )
            ]
            display = fullText
        }

        self.displayText = display
        self.regions = parsedRegions
        self.segments = builtSegments
        self.lineStarts = Self.lineStarts(in: display)

        var markers: [Int: JSONFoldMarker] = [:]
        for region in parsedRegions {
            guard !Self.isHidden(region, by: activeCollapsed) else { continue }
            let displayLocation = Self.displayLocation(
                forSourceLocation: region.range.location,
                segments: builtSegments
            )
            let line = Self.lineNumber(at: displayLocation, lineStarts: self.lineStarts)
            markers[line] = JSONFoldMarker(
                id: region.id,
                isCollapsed: collapsedIDs.contains(region.id)
            )
        }
        self.markerByDisplayLine = markers
    }

    func lineNumber(atDisplayLocation location: Int) -> Int {
        Self.lineNumber(at: location, lineStarts: lineStarts)
    }

    func sourceLocation(forDisplayLocation location: Int) -> Int {
        for segment in segments {
            if location <= NSMaxRange(segment.displayRange) {
                let offset = max(0, min(location - segment.displayRange.location, segment.displayRange.length))
                if segment.isFolded {
                    return offset >= segment.displayRange.length
                        ? NSMaxRange(segment.sourceRange)
                        : segment.sourceRange.location
                }
                return segment.sourceRange.location + offset
            }
        }
        return (fullText as NSString).length
    }

    func displayLocation(forSourceLocation location: Int) -> Int {
        Self.displayLocation(forSourceLocation: location, segments: segments)
    }

    private static func displayLocation(forSourceLocation location: Int, segments: [JSONDisplaySegment]) -> Int {
        for segment in segments {
            if location <= NSMaxRange(segment.sourceRange) {
                if segment.isFolded {
                    return segment.displayRange.location
                }
                let offset = max(0, min(location - segment.sourceRange.location, segment.sourceRange.length))
                return segment.displayRange.location + offset
            }
        }
        return segments.last.map { NSMaxRange($0.displayRange) } ?? 0
    }

    private static func parseFoldRegions(in text: String, lineStarts: [Int]) -> [JSONFoldRegion] {
        let source = text as NSString
        var stack: [(char: Character, location: Int)] = []
        var regions: [JSONFoldRegion] = []
        var index = 0
        var inString = false
        var escaped = false

        while index < source.length {
            let scalar = source.character(at: index)
            let character = Character(UnicodeScalar(scalar)!)
            if inString {
                if escaped {
                    escaped = false
                } else if scalar == 92 {
                    escaped = true
                } else if scalar == 34 {
                    inString = false
                }
                index += 1
                continue
            }

            if scalar == 34 {
                inString = true
            } else if character == "{" || character == "[" {
                stack.append((character, index))
            } else if character == "}" || character == "]" {
                if let last = stack.last,
                   (last.char == "{" && character == "}" || last.char == "[" && character == "]") {
                    stack.removeLast()
                    let startLine = lineNumber(at: last.location, lineStarts: lineStarts)
                    let endLine = lineNumber(at: index, lineStarts: lineStarts)
                    if endLine > startLine {
                        let range = NSRange(location: last.location, length: index - last.location + 1)
                        regions.append(
                            JSONFoldRegion(
                                id: "\(range.location)-\(range.length)",
                                range: range,
                                open: last.char,
                                close: character,
                                startLine: startLine,
                                endLine: endLine
                            )
                        )
                    }
                }
            }
            index += 1
        }

        return regions.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                return lhs.range.length > rhs.range.length
            }
            return lhs.range.location < rhs.range.location
        }
    }

    private static func topLevelCollapsedRegions(_ regions: [JSONFoldRegion]) -> [JSONFoldRegion] {
        var result: [JSONFoldRegion] = []
        for region in regions.sorted(by: { $0.range.location < $1.range.location }) {
            if result.contains(where: { NSLocationInRange(region.range.location, $0.range) }) {
                continue
            }
            result.append(region)
        }
        return result
    }

    private static func isHidden(_ region: JSONFoldRegion, by collapsed: [JSONFoldRegion]) -> Bool {
        collapsed.contains { parent in
            parent.id != region.id
                && region.range.location > parent.range.location
                && NSMaxRange(region.range) <= NSMaxRange(parent.range)
        }
    }

    private static func lineStarts(in text: String) -> [Int] {
        let source = text as NSString
        var starts = [0]
        var index = 0
        while index < source.length {
            if source.character(at: index) == 10 {
                starts.append(index + 1)
            }
            index += 1
        }
        return starts
    }

    private static func lineNumber(at location: Int, lineStarts: [Int]) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= location {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return max(0, high)
    }
}

struct JSONToken {
    let range: NSRange
    let kind: Kind

    enum Kind: Equatable {
        case key
        case string
        case number
        case boolean
        case null
        case punctuation

        var color: NSColor {
            switch self {
            case .key:
                return .systemRed
            case .string:
                return .systemBlue
            case .number:
                return .systemPurple
            case .boolean:
                return .systemOrange
            case .null:
                return .secondaryLabelColor
            case .punctuation:
                return .tertiaryLabelColor
            }
        }
    }
}

enum JSONLexer {
    private static let quote: unichar = 34
    private static let backslash: unichar = 92
    private static let colon: unichar = 58

    static func tokens(in text: String) -> [JSONToken] {
        let source = text as NSString
        var result: [JSONToken] = []
        var index = 0

        while index < source.length {
            let character = source.character(at: index)

            if isWhitespace(character) {
                index += 1
                continue
            }

            if character == quote {
                let range = stringRange(in: source, from: index)
                let kind: JSONToken.Kind = isKey(after: range, in: source) ? .key : .string
                result.append(JSONToken(range: range, kind: kind))
                index = NSMaxRange(range)
                continue
            }

            if isNumberStart(character) {
                let range = numberRange(in: source, from: index)
                result.append(JSONToken(range: range, kind: .number))
                index = NSMaxRange(range)
                continue
            }

            if let literal = literalToken(in: source, from: index) {
                result.append(literal)
                index = NSMaxRange(literal.range)
                continue
            }

            if isPunctuation(character) {
                result.append(JSONToken(range: NSRange(location: index, length: 1), kind: .punctuation))
            }
            index += 1
        }

        return result
    }

    private static func stringRange(in source: NSString, from start: Int) -> NSRange {
        var index = start + 1
        var escaped = false

        while index < source.length {
            let character = source.character(at: index)
            if escaped {
                escaped = false
            } else if character == backslash {
                escaped = true
            } else if character == quote {
                index += 1
                break
            }
            index += 1
        }

        return NSRange(location: start, length: index - start)
    }

    private static func isKey(after range: NSRange, in source: NSString) -> Bool {
        var index = NSMaxRange(range)
        while index < source.length,
              isWhitespace(source.character(at: index)) {
            index += 1
        }
        return index < source.length && source.character(at: index) == colon
    }

    private static func numberRange(in source: NSString, from start: Int) -> NSRange {
        var index = start
        while index < source.length,
              isNumberCharacter(source.character(at: index)) {
            index += 1
        }
        return NSRange(location: start, length: index - start)
    }

    private static func literalToken(in source: NSString, from start: Int) -> JSONToken? {
        let candidates: [(String, JSONToken.Kind)] = [
            ("true", .boolean),
            ("false", .boolean),
            ("null", .null)
        ]

        for (literal, kind) in candidates {
            guard start + literal.utf16.count <= source.length else { continue }
            let range = NSRange(location: start, length: literal.utf16.count)
            if source.substring(with: range) == literal {
                return JSONToken(range: range, kind: kind)
            }
        }
        return nil
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        character == 9 || character == 10 || character == 13 || character == 32
    }

    private static func isNumberStart(_ character: unichar) -> Bool {
        character == 45 || (48...57).contains(character)
    }

    private static func isNumberCharacter(_ character: unichar) -> Bool {
        character == 43
            || character == 45
            || character == 46
            || character == 69
            || character == 101
            || (48...57).contains(character)
    }

    private static func isPunctuation(_ character: unichar) -> Bool {
        character == 44
            || character == 58
            || character == 91
            || character == 93
            || character == 123
            || character == 125
    }
}
