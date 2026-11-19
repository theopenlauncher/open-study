//
//  RichTextEditor.swift
//  open-study
//
//  Rich text notes built on NSTextView (TextKit 1 so native lists and tables
//  work). Content is stored as RTFD in Block.richData and autosaved.
//  Supports: headings, bold/italic/underline, bullet & numbered lists,
//  checklists (clickable ☐), links, images, tables (native table panel),
//  code paragraphs and Markdown-style shortcuts (DESIGN.md §13 Notes).
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SwiftData

enum NoteStyle: String, CaseIterable, Identifiable {
    case body, h1, h2, h3
    var id: String { rawValue }
    var title: String {
        switch self {
        case .body: "Text"
        case .h1: "Heading 1"
        case .h2: "Heading 2"
        case .h3: "Heading 3"
        }
    }
    var font: NSFont {
        switch self {
        case .body: NoteFonts.body
        case .h1: .systemFont(ofSize: 26, weight: .semibold)
        case .h2: .systemFont(ofSize: 20, weight: .semibold)
        case .h3: .systemFont(ofSize: 16, weight: .semibold)
        }
    }
}

enum NoteFonts {
    static let body = NSFont.systemFont(ofSize: 15)
    static let code = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    static var paragraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 3
        p.paragraphSpacing = 4
        return p
    }

    static var defaultAttributes: [NSAttributedString.Key: Any] {
        [.font: body, .foregroundColor: Theme.nsTextPrimary, .paragraphStyle: paragraph]
    }

    static func isMono(_ font: NSFont?) -> Bool {
        font?.fontDescriptor.symbolicTraits.contains(.monoSpace) ?? false
    }
}

// MARK: - Serialization

enum NoteCodec {
    static func load(_ block: Block) -> NSAttributedString {
        if let data = block.richData, let s = NSAttributedString(rtfd: data, documentAttributes: nil) {
            return themed(s)
        }
        return NSAttributedString(string: block.text, attributes: NoteFonts.defaultAttributes)
    }

    /// Re-applies dynamic colours (RTF stores fixed RGB, which would break dark mode).
    static func themed(_ s: NSAttributedString) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: s)
        let full = NSRange(location: 0, length: m.length)
        m.removeAttribute(.foregroundColor, range: full)
        m.removeAttribute(.backgroundColor, range: full)
        m.addAttribute(.foregroundColor, value: Theme.nsTextPrimary, range: full)
        m.enumerateAttribute(.font, in: full) { value, range, _ in
            if NoteFonts.isMono(value as? NSFont) { m.addAttribute(.backgroundColor, value: Theme.nsMuted, range: range) }
        }
        return m
    }

    static func encode(_ s: NSAttributedString) -> Data? {
        let m = NSMutableAttributedString(attributedString: s)
        let full = NSRange(location: 0, length: m.length)
        m.removeAttribute(.foregroundColor, range: full)
        m.removeAttribute(.backgroundColor, range: full)
        return m.rtfd(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
    }

    static func make(plain: String) -> Data? {
        encode(NSAttributedString(string: plain, attributes: NoteFonts.defaultAttributes))
    }
}

// MARK: - Formatter (shared by the floating format bar)

@MainActor
@Observable
final class NoteFormatter {
    @ObservationIgnored weak var textView: NoteTextView?
    var isEditing = false
    var currentStyle: NoteStyle = .body
    @ObservationIgnored private var hideWork: DispatchWorkItem?

    func began(_ tv: NoteTextView) {
        hideWork?.cancel()
        textView = tv
        isEditing = true
        refreshState()
    }

    func ended(_ tv: NoteTextView) {
        guard tv === textView else { return }
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.textView?.window?.firstResponder !== self.textView { self.isEditing = false }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    func refreshState() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let loc = min(tv.selectedRange().location, max(0, storage.length - 1))
        let font = storage.length > 0 ? storage.attribute(.font, at: loc, effectiveRange: nil) as? NSFont : tv.typingAttributes[.font] as? NSFont
        let size = font?.pointSize ?? 15
        currentStyle = size >= 25 ? .h1 : size >= 19 ? .h2 : (size >= 16 && (font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false)) ? .h3 : .body
    }

    // MARK: Helpers

    private var selectedRanges: [NSRange] { textView?.selectedRanges.map(\.rangeValue) ?? [] }

    private func paragraphRanges() -> [NSRange] {
        guard let tv = textView else { return [] }
        let ns = tv.string as NSString
        var result: [NSRange] = []
        for r in selectedRanges {
            var loc = ns.paragraphRange(for: NSRange(location: r.location, length: 0)).location
            let end = r.location + r.length
            repeat {
                let p = ns.paragraphRange(for: NSRange(location: loc, length: 0))
                if !result.contains(p) { result.append(p) }
                loc = p.location + p.length
            } while loc < end && loc < ns.length
        }
        return result
    }

    private func edit(_ ranges: [NSRange], _ body: (NSTextStorage) -> Void) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        guard tv.shouldChangeText(inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: nil) else { return }
        storage.beginEditing()
        body(storage)
        storage.endEditing()
        tv.didChangeText()
        refreshState()
    }

    // MARK: Inline styles

    func toggleTrait(_ trait: NSFontTraitMask) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let fm = NSFontManager.shared
        let ranges = selectedRanges.filter { $0.length > 0 }
        if ranges.isEmpty {
            let font = tv.typingAttributes[.font] as? NSFont ?? NoteFonts.body
            let has = fm.traits(of: font).contains(trait)
            tv.typingAttributes[.font] = has ? fm.convert(font, toNotHaveTrait: trait) : fm.convert(font, toHaveTrait: trait)
            return
        }
        let first = storage.attribute(.font, at: ranges[0].location, effectiveRange: nil) as? NSFont ?? NoteFonts.body
        let has = fm.traits(of: first).contains(trait)
        edit(ranges) { storage in
            for r in ranges {
                storage.enumerateAttribute(.font, in: r) { value, sub, _ in
                    let f = value as? NSFont ?? NoteFonts.body
                    storage.addAttribute(.font, value: has ? fm.convert(f, toNotHaveTrait: trait) : fm.convert(f, toHaveTrait: trait), range: sub)
                }
            }
        }
    }

    func toggleUnderline() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let ranges = selectedRanges.filter { $0.length > 0 }
        if ranges.isEmpty {
            let on = (tv.typingAttributes[.underlineStyle] as? Int ?? 0) != 0
            tv.typingAttributes[.underlineStyle] = on ? 0 : NSUnderlineStyle.single.rawValue
            return
        }
        let on = (storage.attribute(.underlineStyle, at: ranges[0].location, effectiveRange: nil) as? Int ?? 0) != 0
        edit(ranges) { storage in
            for r in ranges {
                if on { storage.removeAttribute(.underlineStyle, range: r) }
                else { storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r) }
            }
        }
    }

    // MARK: Paragraph styles

    func setStyle(_ style: NoteStyle) {
        guard let tv = textView else { return }
        let ranges = paragraphRanges()
        if tv.string.isEmpty || ranges.allSatisfy({ $0.length == 0 }) {
            tv.typingAttributes[.font] = style.font
            currentStyle = style
            return
        }
        edit(ranges) { storage in
            for r in ranges where r.length > 0 { storage.addAttribute(.font, value: style.font, range: r) }
        }
        tv.typingAttributes[.font] = style.font
        currentStyle = style
    }

    func toggleCode() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let ranges = paragraphRanges()
        let probe = ranges.first.map { $0.length > 0 ? storage.attribute(.font, at: $0.location, effectiveRange: nil) as? NSFont : tv.typingAttributes[.font] as? NSFont } ?? nil
        let isCode = NoteFonts.isMono(probe)
        if ranges.allSatisfy({ $0.length == 0 }) {
            tv.typingAttributes[.font] = isCode ? NoteFonts.body : NoteFonts.code
            tv.typingAttributes[.backgroundColor] = isCode ? nil : Theme.nsMuted
            return
        }
        edit(ranges) { storage in
            for r in ranges where r.length > 0 {
                storage.addAttribute(.font, value: isCode ? NoteFonts.body : NoteFonts.code, range: r)
                if isCode { storage.removeAttribute(.backgroundColor, range: r) }
                else { storage.addAttribute(.backgroundColor, value: Theme.nsMuted, range: r) }
            }
        }
    }

    private static func listStyle(_ list: NSTextList?) -> NSParagraphStyle {
        let style = NoteFonts.paragraph.mutableCopy() as! NSMutableParagraphStyle
        if let list {
            style.textLists = [list]
            style.headIndent = 28
            style.tabStops = [NSTextTab(textAlignment: .left, location: 8), NSTextTab(textAlignment: .left, location: 28)]
        }
        return style
    }

    func toggleList(_ format: NSTextList.MarkerFormat) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let ranges = paragraphRanges()
        guard let first = ranges.first, let last = ranges.last else { return }
        let probe = first.location < storage.length
            ? storage.attribute(.paragraphStyle, at: first.location, effectiveRange: nil) as? NSParagraphStyle
            : tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        let removing = probe?.textLists.last?.markerFormat == format
        let list = NSTextList(markerFormat: format, options: 0)
        let style = Self.listStyle(removing ? nil : list)

        let affected = NSRange(location: first.location, length: last.location + last.length - first.location)
        let replacement = NSMutableAttributedString()
        for (i, r) in ranges.enumerated() {
            let line = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: r))
            let s = line.string as NSString
            if s.hasPrefix("\t") && s.length > 1 {
                let second = s.range(of: "\t", options: [], range: NSRange(location: 1, length: s.length - 1))
                if second.location != NSNotFound && second.location < 12 {
                    line.deleteCharacters(in: NSRange(location: 0, length: second.location + 1))
                }
            }
            if !removing {
                var attrs = line.length > 0 ? line.attributes(at: 0, effectiveRange: nil) : tv.typingAttributes
                attrs[.link] = nil
                line.insert(NSAttributedString(string: "\t\(list.marker(forItemNumber: i + 1))\t", attributes: attrs), at: 0)
            }
            if line.length > 0 {
                line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
            }
            replacement.append(line)
        }
        guard tv.shouldChangeText(in: affected, replacementString: replacement.string) else { return }
        storage.replaceCharacters(in: affected, with: replacement)
        tv.didChangeText()
        let rs = replacement.string as NSString
        var firstLen = rs.paragraphRange(for: NSRange(location: 0, length: 0)).length
        if rs.length > 0 && firstLen > 0 && rs.character(at: firstLen - 1) == 10 { firstLen -= 1 }
        tv.setSelectedRange(NSRange(location: affected.location + firstLen, length: 0))
        tv.typingAttributes[.paragraphStyle] = style
    }

    func toggleChecklist() {
        guard let tv = textView, tv.textStorage != nil else { return }
        var ranges = paragraphRanges()
        if ranges.isEmpty { ranges = [NSRange(location: tv.selectedRange().location, length: 0)] }
        let ns = tv.string as NSString
        let removing = ranges.first.map { r in
            r.length >= 2 && ["☐ ", "☑ "].contains(ns.substring(with: NSRange(location: r.location, length: 2)))
        } ?? false
        edit(ranges) { storage in
            for r in ranges.reversed() {
                if removing {
                    if r.length >= 2 {
                        storage.deleteCharacters(in: NSRange(location: r.location, length: 2))
                        let rest = NSRange(location: r.location, length: max(0, r.length - 2))
                        storage.removeAttribute(.strikethroughStyle, range: rest)
                    }
                } else {
                    let attrs = r.location < storage.length ? storage.attributes(at: r.location, effectiveRange: nil) : tv.typingAttributes
                    storage.insert(NSAttributedString(string: "☐ ", attributes: attrs), at: r.location)
                }
            }
        }
        if !removing && ns.length == 0 { tv.setSelectedRange(NSRange(location: 2, length: 0)) }
    }

    // MARK: Insertions

    func insertLink(_ urlString: String, selection: NSRange) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        var s = urlString.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        if !s.contains("://") && !s.hasPrefix("mailto:") { s = "https://" + s }
        guard let url = URL(string: s) else { return }
        if selection.length > 0 {
            edit([selection]) { $0.addAttribute(.link, value: url, range: selection) }
        } else {
            var attrs = tv.typingAttributes
            attrs[.link] = url
            let text = NSAttributedString(string: urlString, attributes: attrs)
            if tv.shouldChangeText(in: selection, replacementString: text.string) {
                storage.replaceCharacters(in: selection, with: text)
                tv.didChangeText()
                tv.setSelectedRange(NSRange(location: selection.location + text.length, length: 0))
                tv.typingAttributes[.link] = nil
            }
        }
    }

    func insertImage() {
        guard let tv = textView else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an image to insert into your note."
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        guard let attachment = Self.attachment(for: image) else { return }
        let str = NSMutableAttributedString(attachment: attachment)
        str.addAttributes(NoteFonts.defaultAttributes, range: NSRange(location: 0, length: str.length))
        let range = tv.selectedRange()
        if tv.shouldChangeText(in: range, replacementString: str.string) {
            tv.textStorage?.replaceCharacters(in: range, with: str)
            tv.didChangeText()
        }
        tv.window?.makeFirstResponder(tv)
    }

    /// Downscales to a sensible width and embeds as PNG so it survives RTFD round-trips.
    static func attachment(for image: NSImage, maxWidth: CGFloat = 560) -> NSTextAttachment? {
        let scale = min(1, maxWidth / max(1, image.size.width))
        let size = NSSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let wrapper = FileWrapper(regularFileWithContents: png)
        wrapper.preferredFilename = "image.png"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        let display = NSImage(size: size)
        display.addRepresentation(rep)
        attachment.image = display
        return attachment
    }

    func insertTable() {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
        tv.orderFrontTablePanel(nil)
    }

    var selection: NSRange { textView?.selectedRange() ?? NSRange(location: 0, length: 0) }
}

// MARK: - NSTextView subclass

final class NoteTextView: NSTextView {
    var placeholder = ""
    var onFocusChange: ((Bool) -> Void)?

    override var intrinsicContentSize: NSSize {
        guard let lm = layoutManager, let tc = textContainer else { return super.intrinsicContentSize }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).height
        return NSSize(width: NSView.noIntrinsicMetric, height: max(24, ceil(used + textContainerInset.height * 2)))
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged {
            textContainer?.size = NSSize(width: newSize.width - textContainerInset.width * 2, height: .greatestFiniteMagnitude)
            invalidateIntrinsicContentSize()
        }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocusChange?(true); needsDisplay = true }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onFocusChange?(false); needsDisplay = true }
        return ok
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty && !placeholder.isEmpty && window?.firstResponder === self {
            let attrs: [NSAttributedString.Key: Any] = [.font: NoteFonts.body, .foregroundColor: Theme.nsTextTertiary]
            (placeholder as NSString).draw(at: NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
                                                       y: textContainerInset.height), withAttributes: attrs)
        }
    }

    /// Clicking a ☐ / ☑ marker toggles it.
    override func mouseDown(with event: NSEvent) {
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage else { return super.mouseDown(with: event) }
        let p = convert(event.locationInWindow, from: nil)
        let point = NSPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y)
        let glyph = lm.glyphIndex(for: point, in: tc, fractionOfDistanceThroughGlyph: nil)
        let rect = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc).insetBy(dx: -2, dy: -2)
        let index = lm.characterIndexForGlyph(at: glyph)
        if rect.contains(point), index < storage.length {
            let ch = (string as NSString).substring(with: NSRange(location: index, length: 1))
            if ch == "☐" || ch == "☑" {
                let para = (string as NSString).paragraphRange(for: NSRange(location: index, length: 0))
                let checking = ch == "☐"
                let markerRange = NSRange(location: index, length: 1)
                if shouldChangeText(in: para, replacementString: nil) {
                    storage.beginEditing()
                    storage.replaceCharacters(in: markerRange, with: checking ? "☑" : "☐")
                    let rest = NSRange(location: index + 2, length: max(0, para.location + para.length - index - 2))
                    if rest.length > 0 {
                        if checking { storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: rest) }
                        else { storage.removeAttribute(.strikethroughStyle, range: rest) }
                    }
                    storage.endEditing()
                    didChangeText()
                }
                return
            }
        }
        super.mouseDown(with: event)
    }
}

// MARK: - SwiftUI bridge

struct RichTextEditor: NSViewRepresentable {
    let block: Block
    let formatter: NoteFormatter
    var autoFocus = false
    var onSlash: () -> Void = {}
    var onAutoFocused: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(block: block, formatter: formatter, onSlash: onSlash) }

    func makeNSView(context: Context) -> NoteTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)

        let tv = NoteTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 24), textContainer: container)
        tv.isRichText = true
        tv.importsGraphics = true
        tv.allowsImageEditing = false
        tv.allowsUndo = true
        tv.usesFontPanel = false
        tv.usesRuler = false
        tv.isAutomaticLinkDetectionEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.drawsBackground = false
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.textContainerInset = NSSize(width: 0, height: 3)
        tv.typingAttributes = NoteFonts.defaultAttributes
        tv.defaultParagraphStyle = NoteFonts.paragraph
        tv.linkTextAttributes = [.foregroundColor: Theme.nsAccent, .underlineStyle: NSUnderlineStyle.single.rawValue, .cursor: NSCursor.pointingHand]
        tv.selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor]
        tv.placeholder = "Write something, or press / for blocks"
        tv.setAccessibilityLabel("Note")

        storage.setAttributedString(NoteCodec.load(block))
        tv.delegate = context.coordinator
        context.coordinator.textView = tv
        tv.onFocusChange = { [weak tv, weak formatter] focused in
            guard let tv, let formatter else { return }
            if focused { formatter.began(tv) } else { formatter.ended(tv) }
        }
        return tv
    }

    func updateNSView(_ tv: NoteTextView, context: Context) {
        context.coordinator.onSlash = onSlash
        if autoFocus {
            DispatchQueue.main.async {
                tv.window?.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
                onAutoFocused()
            }
        }
    }

    static func dismantleNSView(_ tv: NoteTextView, coordinator: Coordinator) {
        coordinator.flush()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let block: Block
        let formatter: NoteFormatter
        var onSlash: () -> Void
        weak var textView: NoteTextView?
        private var saveWork: DispatchWorkItem?

        init(block: Block, formatter: NoteFormatter, onSlash: @escaping () -> Void) {
            self.block = block
            self.formatter = formatter
            self.onSlash = onSlash
        }

        private var dirty = false

        func textDidChange(_ notification: Notification) {
            dirty = true
            saveWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.flush() }
            saveWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if formatter.textView === textView { formatter.refreshState() }
        }

        func flush() {
            saveWork?.cancel()
            saveWork = nil
            guard dirty, let tv = textView, let storage = tv.textStorage, block.modelContext != nil else { return }
            dirty = false
            block.text = storage.string
            block.richData = NoteCodec.encode(storage)
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            guard let text, range.length == 0 else { return true }
            let ns = textView.string as NSString
            let para = ns.paragraphRange(for: NSRange(location: range.location, length: 0))
            let prefix = ns.substring(with: NSRange(location: para.location, length: range.location - para.location))

            // "/" on an empty line opens the block menu.
            if text == "/" && prefix.isEmpty {
                let paraText = ns.substring(with: para).trimmingCharacters(in: .newlines)
                if paraText.isEmpty {
                    DispatchQueue.main.async { self.onSlash() }
                    return false
                }
            }

            // Markdown-style shortcuts at the start of a paragraph.
            if text == " " {
                let action: (() -> Void)?
                switch prefix {
                case "#": action = { self.formatter.setStyle(.h1) }
                case "##": action = { self.formatter.setStyle(.h2) }
                case "###": action = { self.formatter.setStyle(.h3) }
                case "-", "*": action = { self.formatter.toggleList(.disc) }
                case "1.": action = { self.formatter.toggleList(.decimal) }
                case "[]": action = { self.formatter.toggleChecklist() }
                default: action = nil
                }
                if let action {
                    let prefixRange = NSRange(location: para.location, length: prefix.utf16.count)
                    DispatchQueue.main.async {
                        guard textView.shouldChangeText(in: prefixRange, replacementString: "") else { return }
                        textView.textStorage?.replaceCharacters(in: prefixRange, with: "")
                        textView.didChangeText()
                        textView.setSelectedRange(NSRange(location: para.location, length: 0))
                        action()
                    }
                    return false
                }
            }
            if text == "`" && prefix == "``" {
                let prefixRange = NSRange(location: para.location, length: 2)
                DispatchQueue.main.async {
                    guard textView.shouldChangeText(in: prefixRange, replacementString: "") else { return }
                    textView.textStorage?.replaceCharacters(in: prefixRange, with: "")
                    textView.didChangeText()
                    textView.setSelectedRange(NSRange(location: para.location, length: 0))
                    self.formatter.toggleCode()
                }
                return false
            }
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let ns = textView.string as NSString
            let sel = textView.selectedRange()
            let para = ns.paragraphRange(for: NSRange(location: sel.location, length: 0))
            let line = ns.substring(with: para).trimmingCharacters(in: .newlines)
            guard line.hasPrefix("☐ ") || line.hasPrefix("☑ ") || line == "☐" || line == "☑" else { return false }
            if line.count <= 2 {
                // Empty checklist item: end the checklist.
                let markerRange = NSRange(location: para.location, length: min(2, para.length))
                if textView.shouldChangeText(in: markerRange, replacementString: "") {
                    textView.textStorage?.replaceCharacters(in: markerRange, with: "")
                    textView.didChangeText()
                }
                return true
            }
            var attrs = textView.typingAttributes
            attrs[.strikethroughStyle] = nil
            let insert = NSAttributedString(string: "\n☐ ", attributes: attrs)
            if textView.shouldChangeText(in: sel, replacementString: insert.string) {
                textView.textStorage?.replaceCharacters(in: sel, with: insert)
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: sel.location + insert.length, length: 0))
                textView.typingAttributes = attrs
            }
            return true
        }
    }
}

// MARK: - Floating format bar

struct NoteFormatBar: View {
    let formatter: NoteFormatter
    @State private var showLink = false
    @State private var linkText = ""
    @State private var linkSelection = NSRange(location: 0, length: 0)

    var body: some View {
        HStack(spacing: 2) {
            Menu {
                ForEach(NoteStyle.allCases) { style in
                    Button(style.title) { formatter.setStyle(style) }
                }
            } label: {
                Text(formatter.currentStyle.title).font(Typo.bodyMedium)
            }
            .menuStyle(.button)
            .buttonStyle(.osGhost)
            .fixedSize()
            .help("Paragraph style")

            bar
            Button {
                linkSelection = formatter.selection
                linkText = ""
                showLink = true
            } label: { glyph("link") }
            .buttonStyle(.plain)
            .help("Add link")
            .popover(isPresented: $showLink, arrowEdge: .top) {
                HStack {
                    TextField("Paste or type a link", text: $linkText)
                        .textFieldStyle(.os)
                        .frame(width: 240)
                        .onSubmit(applyLink)
                    Button("Add", action: applyLink).buttonStyle(.osPrimary)
                }
                .padding(Space.md)
            }
            formatButton("photo", "Insert image") { formatter.insertImage() }
            formatButton("tablecells", "Insert table") { formatter.insertTable() }
        }
        .padding(4)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous).strokeBorder(Theme.border))
        .floatShadow()
    }

    @ViewBuilder private var bar: some View {
        divider
        formatButton("bold", "Bold (⌘B)") { formatter.toggleTrait(.boldFontMask) }
        formatButton("italic", "Italic (⌘I)") { formatter.toggleTrait(.italicFontMask) }
        formatButton("underline", "Underline (⌘U)") { formatter.toggleUnderline() }
        divider
        formatButton("list.bullet", "Bulleted list  (type “- ”)") { formatter.toggleList(.disc) }
        formatButton("list.number", "Numbered list  (type “1. ”)") { formatter.toggleList(.decimal) }
        formatButton("checklist", "Checklist  (type “[] ”)") { formatter.toggleChecklist() }
        formatButton("chevron.left.forwardslash.chevron.right", "Code  (type ```)") { formatter.toggleCode() }
        divider
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(width: 1, height: 18).padding(.horizontal, 3)
    }

    private func glyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13))
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 28, height: 26)
            .contentShape(Rectangle())
            .hoverHighlight(cornerRadius: 6)
    }

    private func formatButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { glyph(symbol) }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(help)
    }

    private func applyLink() {
        formatter.insertLink(linkText, selection: linkSelection)
        showLink = false
    }
}
