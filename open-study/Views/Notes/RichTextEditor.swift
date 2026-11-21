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
            let m = NSMutableAttributedString(attributedString: themed(s))
            restoreListMarkers(m)
            NoteImages.prepare(m)
            return m
        }
        return NSAttributedString(string: block.text, attributes: NoteFonts.defaultAttributes)
    }

    /// TextKit 1 lists are drawn from literal "\t•\t" marker text, but RTFD
    /// treats that text as list decoration and drops it when reading back.
    /// The paragraphs keep their `textLists`, so the markers are rebuilt here.
    static func restoreListMarkers(_ m: NSMutableAttributedString) {
        let ns = m.string as NSString
        var inserts: [(Int, NSAttributedString)] = []
        var loc = 0
        // Each list created by toggleList is its own NSTextList, and RTFD keeps
        // them distinct, so numbering is tracked per list: adjacent separate
        // lists restart, and an outer list continues after nested items.
        var counters: [ObjectIdentifier: Int] = [:]
        var number = 0
        while loc < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            loc = para.location + para.length
            let style = m.attribute(.paragraphStyle, at: para.location, effectiveRange: nil) as? NSParagraphStyle
            let chain = style?.textLists ?? []
            // Lists that don't enclose this paragraph have ended.
            let open = Set(chain.map(ObjectIdentifier.init))
            counters = counters.filter { open.contains($0.key) }
            guard let list = chain.last else { continue }
            number = counters[ObjectIdentifier(list)].map { $0 + 1 } ?? list.startingItemNumber
            counters[ObjectIdentifier(list)] = number
            if ns.substring(with: para).hasPrefix("\t") { continue }
            var attrs = m.attributes(at: para.location, effectiveRange: nil)
            attrs[.link] = nil
            attrs[.attachment] = nil
            inserts.append((para.location, NSAttributedString(string: "\t\(list.marker(forItemNumber: number))\t", attributes: attrs)))
        }
        for (at, marker) in inserts.reversed() { m.insert(marker, at: at) }
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

// MARK: - Images

/// Draws an image attachment at a chosen size, never wider than the text
/// it sits in (wide images used to be clipped by the note's edge).
nonisolated final class ResizableImageCell: NSTextAttachmentCell {
    var displaySize: NSSize

    @MainActor init(image: NSImage, displaySize: NSSize) {
        self.displaySize = displaySize
        super.init(imageCell: image)
    }

    @MainActor required init(coder: NSCoder) {
        displaySize = .zero
        super.init(coder: coder)
    }

    override func cellSize() -> NSSize { displaySize }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        var size = displaySize
        let available = max(NoteImages.minWidth, lineFrag.width - textContainer.lineFragmentPadding * 2)
        if size.width > available {
            size = NSSize(width: available, height: (size.height * available / max(1, size.width)).rounded())
        }
        return NSRect(origin: .zero, size: size)
    }

    @MainActor override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        image?.draw(in: cellFrame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high])
    }

    @MainActor override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int) {
        draw(withFrame: cellFrame, in: controlView)
    }

    @MainActor override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int, layoutManager: NSLayoutManager) {
        draw(withFrame: cellFrame, in: controlView)
    }
}

enum NoteImages {
    nonisolated static let minWidth: CGFloat = 48
    /// Pixel width cap for stored images: sharp at full reading width on Retina, without bloating notes.
    static let maxPixelWidth: CGFloat = 1800

    /// The picture an attachment holds, or nil when it isn't an image.
    /// File-backed attachments must decode as an image file: other files
    /// (a ZIP, a PDF, a folder) keep their data, and their cell's file icon
    /// is never mistaken for content.
    static func image(of attachment: NSTextAttachment) -> NSImage? {
        if let wrapper = attachment.fileWrapper {
            // `regularFileContents` raises for directory and symlink wrappers.
            guard wrapper.isRegularFile, let data = wrapper.regularFileContents else { return nil }
            if let name = wrapper.preferredFilename ?? wrapper.filename,
               let type = UTType(filenameExtension: (name as NSString).pathExtension), !type.conforms(to: .image) {
                return nil
            }
            guard !NSBitmapImageRep.imageReps(with: data).isEmpty else { return nil }
            return NSImage(data: data)
        }
        if let image = attachment.image { return image }
        return (attachment.attachmentCell as? NSCell)?.image
    }

    /// Embeds `image` as PNG displayed `width` points wide. The display size is
    /// written as the PNG's resolution, so it survives the RTFD round-trip.
    static func attachment(for image: NSImage, width: CGFloat) -> NSTextAttachment? {
        let width = max(minWidth, width.rounded())
        let size = NSSize(width: width, height: max(1, (image.size.height * width / max(1, image.size.width)).rounded()))
        let sourcePixels = CGFloat(image.representations.map(\.pixelsWide).max() ?? 0)
        // Bitmaps keep their own pixels (capped): upsampling adds memory, not
        // detail. Sources without pixel dimensions (vector) render at 2×.
        let pixelWidth = min(maxPixelWidth, sourcePixels > 0 ? sourcePixels : width * 2)
        let pixelHeight = max(1, (pixelWidth * size.height / size.width).rounded())
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixelWidth), pixelsHigh: Int(pixelHeight),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: pixelWidth, height: pixelHeight)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        NSGraphicsContext.restoreGraphicsState()
        return attachment(rep: rep, size: size)
    }

    /// The same pixels, stored at a new display size.
    static func resized(_ cell: ResizableImageCell, to size: NSSize) -> NSTextAttachment? {
        guard let image = cell.image else { return nil }
        guard let source = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
              let rep = source.copy() as? NSBitmapImageRep else {
            return attachment(for: image, width: size.width) // e.g. a vector image: rasterise it
        }
        return attachment(rep: rep, size: size)
    }

    private static func attachment(rep: NSBitmapImageRep, size: NSSize) -> NSTextAttachment? {
        rep.size = size
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let wrapper = FileWrapper(regularFileWithContents: png)
        wrapper.preferredFilename = "image.png"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        let display = NSImage(size: size)
        display.addRepresentation(rep)
        attachment.attachmentCell = ResizableImageCell(image: display, displaySize: size)
        return attachment
    }

    /// Gives loaded images a resizable cell. Their stored size is kept; the
    /// cell only shrinks them to fit when the note is narrower.
    static func prepare(_ m: NSMutableAttributedString) {
        m.enumerateAttribute(.attachment, in: NSRange(location: 0, length: m.length)) { value, _, _ in
            guard let attachment = value as? NSTextAttachment, !(attachment.attachmentCell is ResizableImageCell),
                  let image = image(of: attachment), image.size.width > 0 else { return }
            attachment.attachmentCell = ResizableImageCell(image: image, displaySize: image.size)
        }
    }
}

// MARK: - Formatter (shared by the floating format bar)

@MainActor
@Observable
final class NoteFormatter {
    @ObservationIgnored weak var textView: NoteTextView?
    var isEditing = false
    var currentStyle: NoteStyle = .body
    /// Formatting at the caret / start of the selection, shown as active
    /// buttons in the format bar.
    var isBold = false
    var isItalic = false
    var isUnderline = false
    var isCode = false
    var isChecklist = false
    var listFormat: NSTextList.MarkerFormat?
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
        let sel = tv.selectedRange()
        // With a caret, typing attributes are what the next keystroke gets
        // (including a just-toggled B/I/U); with a selection, read the text.
        let attrs: [NSAttributedString.Key: Any]
        if sel.length > 0, sel.location < storage.length {
            attrs = storage.attributes(at: sel.location, effectiveRange: nil)
        } else {
            attrs = tv.typingAttributes
        }
        let font = attrs[.font] as? NSFont ?? NoteFonts.body
        let traits = NSFontManager.shared.traits(of: font)
        let size = font.pointSize
        let headingSized = size >= 16
        currentStyle = size >= 25 ? .h1 : size >= 19 ? .h2 : (headingSized && traits.contains(.boldFontMask)) ? .h3 : .body
        // Headings are semibold by definition, so B only lights up for body text.
        isBold = !headingSized && traits.contains(.boldFontMask)
        isItalic = traits.contains(.italicFontMask)
        isUnderline = (attrs[.underlineStyle] as? Int ?? 0) != 0
        isCode = NoteFonts.isMono(font)

        let ns = tv.string as NSString
        let para = ns.paragraphRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
        let style = para.location < storage.length
            ? storage.attribute(.paragraphStyle, at: para.location, effectiveRange: nil) as? NSParagraphStyle
            : tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        listFormat = style?.textLists.last?.markerFormat
        let head = para.length >= 1 ? ns.substring(with: NSRange(location: para.location, length: 1)) : ""
        isChecklist = head == "☐" || head == "☑"
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

    /// Format bar / ⌘B / ⌘I: flips the trait based on the start of the selection.
    func toggleTrait(_ trait: NSFontTraitMask) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let fm = NSFontManager.shared
        let ranges = selectedRanges.filter { $0.length > 0 }
        let probe = ranges.first.map { storage.attribute(.font, at: $0.location, effectiveRange: nil) as? NSFont }
            ?? tv.typingAttributes[.font] as? NSFont
        setTrait(trait, on: !fm.traits(of: probe ?? NoteFonts.body).contains(trait))
    }

    /// Adds or removes a trait on every selected run (or the typing font with
    /// a caret). Used by the Font menu, which states the direction explicitly.
    func setTrait(_ trait: NSFontTraitMask, on: Bool) {
        guard let tv = textView, tv.textStorage != nil else { return }
        let fm = NSFontManager.shared
        func apply(_ f: NSFont) -> NSFont { on ? fm.convert(f, toHaveTrait: trait) : fm.convert(f, toNotHaveTrait: trait) }
        let ranges = selectedRanges.filter { $0.length > 0 }
        if ranges.isEmpty {
            tv.typingAttributes[.font] = apply(tv.typingAttributes[.font] as? NSFont ?? NoteFonts.body)
            refreshState()
            return
        }
        edit(ranges) { storage in
            for r in ranges {
                storage.enumerateAttribute(.font, in: r) { value, sub, _ in
                    storage.addAttribute(.font, value: apply(value as? NSFont ?? NoteFonts.body), range: sub)
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
            refreshState()
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
            refreshState()
            currentStyle = style
            return
        }
        edit(ranges) { storage in
            for r in ranges where r.length > 0 { storage.addAttribute(.font, value: style.font, range: r) }
        }
        tv.typingAttributes[.font] = style.font
        // The style font replaces any bold/italic, so the B/I state must follow.
        refreshState()
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
            refreshState()
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
        refreshState()
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
        refreshState()
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
        tv.window?.makeFirstResponder(tv)
        tv.insertImages([image])
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
    weak var formatter: NoteFormatter?

    // MARK: Formatting shortcuts

    /// ⌘B / ⌘I / ⌘U go through the formatter so they behave exactly like the
    /// format bar (the font panel route is disabled via `usesFontPanel`).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, let formatter, formatter.textView === self,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "b": formatter.toggleTrait(.boldFontMask)
        case "i": formatter.toggleTrait(.italicFontMask)
        case "u": formatter.toggleUnderline()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    /// Format ▸ Font menu items (Bold, Italic) arrive as `addFontTrait:` from
    /// the shared font manager.
    override func changeFont(_ sender: Any?) {
        guard let formatter, formatter.textView === self, let fm = sender as? NSFontManager else { return super.changeFont(sender) }
        // Probe what the pending font-manager action does: adding a trait shows
        // on a plain font, removing one shows on a font that already has it.
        // The direction is applied to the whole selection as requested, so
        // mixed selections and bold headings behave correctly.
        for trait in [NSFontTraitMask.boldFontMask, .italicFontMask] {
            let plain = NoteFonts.body
            let styled = fm.convert(plain, toHaveTrait: trait)
            let adds = fm.traits(of: fm.convert(plain)).contains(trait)
            let removes = fm.traits(of: styled).contains(trait) && !fm.traits(of: fm.convert(styled)).contains(trait)
            guard adds || removes else { continue }
            formatter.setTrait(trait, on: adds)
            return
        }
        // Not a bold/italic action (e.g. a size change): let NSTextView handle it.
        super.changeFont(sender)
    }

    override func underline(_ sender: Any?) {
        guard let formatter, formatter.textView === self else { return super.underline(sender) }
        formatter.toggleUnderline()
    }

    /// Last measured height. Returned from `intrinsicContentSize` so SwiftUI
    /// layout passes don't re-run text layout.
    private var cachedHeight: CGFloat?

    private func measuredHeight() -> CGFloat {
        guard let lm = layoutManager, let tc = textContainer else { return 24 }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).height
        return max(24, ceil(used + textContainerInset.height * 2))
    }

    override var intrinsicContentSize: NSSize {
        guard layoutManager != nil else { return super.intrinsicContentSize }
        let height = cachedHeight ?? measuredHeight()
        cachedHeight = height
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    override func didChangeText() {
        super.didChangeText()
        refreshHeight()
    }

    /// Only asks SwiftUI to re-layout the page when the note actually grows
    /// or shrinks; most keystrokes don't change the height.
    func refreshHeight() {
        let height = measuredHeight()
        if height != cachedHeight {
            cachedHeight = height
            invalidateIntrinsicContentSize()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged {
            textContainer?.size = NSSize(width: newSize.width - textContainerInset.width * 2, height: .greatestFiniteMagnitude)
            refreshHeight()
        }
    }

    // MARK: Images

    /// Widest an image may be drawn: the note's text width.
    var maxImageWidth: CGFloat {
        max(NoteImages.minWidth, (textContainer?.size.width ?? frame.width) - 2 * (textContainer?.lineFragmentPadding ?? 0))
    }

    /// Inserts images at the selection, scaled to fit the note.
    func insertImages(_ images: [NSImage]) {
        let str = NSMutableAttributedString()
        for image in images {
            guard let attachment = NoteImages.attachment(for: image, width: min(maxImageWidth, image.size.width)) else { continue }
            str.append(NSAttributedString(attachment: attachment))
        }
        guard str.length > 0 else { return }
        var attrs = typingAttributes
        attrs[.link] = nil
        str.addAttributes(attrs, range: NSRange(location: 0, length: str.length))
        let range = selectedRange()
        if shouldChangeText(in: range, replacementString: str.string) {
            textStorage?.replaceCharacters(in: range, with: str)
            didChangeText()
            setSelectedRange(NSRange(location: range.location + str.length, length: 0))
        }
    }

    /// Pasted or dropped images: plain image data is embedded through
    /// `insertImages`; rich content is pasted natively and any images in it
    /// are then converted so they fit and can be resized.
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        let richTypes: [NSPasteboard.PasteboardType] = [.rtfd, .rtf, .string, .html]
        let hasRichText = pboard.availableType(from: richTypes) != nil
        if !hasRichText, let images = pboard.readObjects(forClasses: [NSImage.self]) as? [NSImage], !images.isEmpty {
            insertImages(images)
            return true
        }
        let before = (string as NSString).length
        let replaced = selectedRange()
        guard super.readSelection(from: pboard, type: type) else { return false }
        // The pasted text replaced the selection: its length is the growth plus what was replaced.
        let pasted = (string as NSString).length - before + replaced.length
        normalizeImages(in: NSRange(location: replaced.location, length: max(0, pasted)))
        return true
    }

    /// Converts foreign image attachments in `range` into resizable ones that fit the note.
    func normalizeImages(in range: NSRange) {
        guard let storage = textStorage else { return }
        let r = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        guard r.length > 0 else { return }
        var changes: [(NSRange, NSTextAttachment)] = []
        storage.enumerateAttribute(.attachment, in: r) { value, sub, _ in
            guard let old = value as? NSTextAttachment, !(old.attachmentCell is ResizableImageCell),
                  let image = NoteImages.image(of: old),
                  let fresh = NoteImages.attachment(for: image, width: min(maxImageWidth, image.size.width)) else { return }
            changes.append((sub, fresh))
        }
        guard !changes.isEmpty else { return }
        storage.beginEditing()
        for (sub, fresh) in changes { storage.addAttribute(.attachment, value: fresh, range: sub) }
        storage.endEditing()
        didChangeText()
    }

    /// The selected image, when the selection is exactly one image.
    private var selectedImage: (index: Int, cell: ResizableImageCell, rect: NSRect)? {
        let sel = selectedRange()
        guard sel.length == 1 else { return nil }
        return image(at: sel.location)
    }

    private func image(at index: Int) -> (index: Int, cell: ResizableImageCell, rect: NSRect)? {
        guard let storage = textStorage, let lm = layoutManager, index < storage.length,
              let attachment = storage.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment,
              let cell = attachment.attachmentCell as? ResizableImageCell else { return nil }
        let glyphs = lm.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        let line = lm.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let loc = lm.location(forGlyphAt: glyphs.location)
        let size = lm.attachmentSize(forGlyphAt: glyphs.location)
        guard size.width > 0 else { return nil }
        // Attachments sit on the baseline: their bottom edge is at the glyph location.
        let rect = NSRect(x: line.minX + loc.x, y: line.minY + loc.y - size.height, width: size.width, height: size.height)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        return (index, cell, rect)
    }

    private func imageIndex(at point: NSPoint) -> Int? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let p = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = lm.glyphIndex(for: p, in: tc, fractionOfDistanceThroughGlyph: nil)
        let index = lm.characterIndexForGlyph(at: glyph)
        guard let hit = image(at: index), hit.rect.contains(point) else { return nil }
        return index
    }

    private static let handleSize: CGFloat = 10

    private func handleRect(for rect: NSRect) -> NSRect {
        let s = Self.handleSize
        return NSRect(x: rect.maxX - s / 2 - 1, y: rect.maxY - s / 2 - 1, width: s, height: s)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if let selected = selectedImage {
            addCursorRect(handleRect(for: selected.rect).insetBy(dx: -3, dy: -3), cursor: .frameResize(position: .bottomRight, directions: .all))
        }
    }

    /// Drags the selected image's corner handle. The size updates live; the
    /// new size is stored in the image itself (PNG resolution) on release so
    /// it survives saving.
    private func trackResize(_ hit: (index: Int, cell: ResizableImageCell, rect: NSRect), from start: NSPoint) {
        let startSize = hit.rect.size
        let original = hit.cell.displaySize
        let aspect = startSize.height / max(1, startSize.width)
        var size = startSize
        var moved = false
        let charRange = NSRange(location: hit.index, length: 1)
        while let event = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let p = convert(event.locationInWindow, from: nil)
            if p != start { moved = true }
            // Follow whichever axis moved further so diagonal drags feel natural.
            let dx = p.x - start.x
            let dy = (p.y - start.y) / max(aspect, 0.01)
            let w = min(maxImageWidth, max(NoteImages.minWidth, startSize.width + (abs(dx) >= abs(dy) ? dx : dy))).rounded()
            size = NSSize(width: w, height: (w * aspect).rounded())
            hit.cell.displaySize = size
            layoutManager?.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
            refreshHeight()
            needsDisplay = true
            if event.type == .leftMouseUp { break }
        }
        hit.cell.displaySize = original
        // A click without a drag keeps the stored size: committing the displayed
        // (possibly width-clamped) size would shrink the image for good.
        guard moved, size != startSize else {
            layoutManager?.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
            refreshHeight()
            needsDisplay = true
            return
        }
        setImageSize(at: hit.index, to: size)
    }

    /// Replaces the image at `index` with one stored at `size` (undoable).
    func setImageSize(at index: Int, to size: NSSize) {
        guard let storage = textStorage, let hit = image(at: index),
              let fresh = NoteImages.resized(hit.cell, to: size) else { return }
        let range = NSRange(location: index, length: 1)
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        storage.addAttribute(.attachment, value: fresh, range: range)
        didChangeText()
        setSelectedRange(range)
        undoManager?.setActionName("Resize Image")
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let base = super.menu(for: event)
        let point = convert(event.locationInWindow, from: nil)
        guard let index = imageIndex(at: point) else { return base }
        setSelectedRange(NSRange(location: index, length: 1))
        let menu = NSMenu()
        let sizes: [(String, CGFloat)] = [("Small", 1.0 / 3), ("Medium", 0.5), ("Large", 0.75), ("Fit Width", 1)]
        for (title, fraction) in sizes {
            let item = NSMenuItem(title: title, action: #selector(resizeFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [index, fraction] as [Any]
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for item in base?.items ?? [] {
            base?.removeItem(item)
            menu.addItem(item)
        }
        return menu
    }

    @objc private func resizeFromMenu(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [Any], let index = info[0] as? Int, let fraction = info[1] as? CGFloat,
              let hit = image(at: index) else { return }
        let aspect = hit.rect.height / max(1, hit.rect.width)
        let w = max(NoteImages.minWidth, (maxImageWidth * fraction).rounded())
        setImageSize(at: index, to: NSSize(width: w, height: (w * aspect).rounded()))
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
        if let selected = selectedImage, window?.firstResponder === self {
            let outline = NSBezierPath(rect: selected.rect.insetBy(dx: -1, dy: -1))
            outline.lineWidth = 2
            Theme.nsAccent.setStroke()
            outline.stroke()
            let handle = NSBezierPath(roundedRect: handleRect(for: selected.rect), xRadius: 2, yRadius: 2)
            NSColor.white.setFill()
            handle.fill()
            handle.lineWidth = 1.5
            handle.stroke()
        }
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

        // Images: the corner handle of a selected image resizes it; a click
        // on an unselected image selects it (a second press drags it as usual).
        if let selected = selectedImage, handleRect(for: selected.rect).insetBy(dx: -4, dy: -4).contains(p) {
            window?.makeFirstResponder(self)
            trackResize(selected, from: p)
            return
        }
        if event.clickCount == 1, let index = imageIndex(at: p), selectedRange() != NSRange(location: index, length: 1) {
            window?.makeFirstResponder(self)
            setSelectedRange(NSRange(location: index, length: 1))
            return
        }
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
        tv.formatter = formatter
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
        formatButton("bold", "Bold (⌘B)", active: formatter.isBold) { formatter.toggleTrait(.boldFontMask) }
        formatButton("italic", "Italic (⌘I)", active: formatter.isItalic) { formatter.toggleTrait(.italicFontMask) }
        formatButton("underline", "Underline (⌘U)", active: formatter.isUnderline) { formatter.toggleUnderline() }
        divider
        formatButton("list.bullet", "Bulleted list  (type “- ”)", active: formatter.listFormat == .disc) { formatter.toggleList(.disc) }
        formatButton("list.number", "Numbered list  (type “1. ”)", active: formatter.listFormat == .decimal) { formatter.toggleList(.decimal) }
        formatButton("checklist", "Checklist  (type “[] ”)", active: formatter.isChecklist) { formatter.toggleChecklist() }
        formatButton("chevron.left.forwardslash.chevron.right", "Code  (type ```)", active: formatter.isCode) { formatter.toggleCode() }
        divider
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(width: 1, height: 18).padding(.horizontal, 3)
    }

    /// `active` marks formatting applied at the caret/selection (DESIGN.md §13 Notes):
    /// a soft `sidebarActive` pill with a `textPrimary` icon, like other selected states.
    private func glyph(_ symbol: String, active: Bool = false) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
            .frame(width: 28, height: 26)
            .background(active ? Theme.sidebarActive : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .hoverHighlight(cornerRadius: 6)
            .animation(Motion.hover, value: active)
    }

    private func formatButton(_ symbol: String, _ help: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { glyph(symbol, active: active) }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(help)
            .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func applyLink() {
        formatter.insertLink(linkText, selection: linkSelection)
        showLink = false
    }
}
