//
//  DocumentStore.swift
//  open-study
//
//  Imported PDFs are copied into the app's own container so they keep working
//  even if the original is moved or deleted. Annotations are written back into
//  the stored copy. One shared PDFDocument instance per file keeps an inline
//  block and a reader window in sync.
//

import Foundation
import PDFKit
import UniformTypeIdentifiers
import AppKit

enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("OpenStudy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var documentsDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var storeURL: URL { supportDirectory.appendingPathComponent("OpenStudy.store") }
}

enum DocumentError: LocalizedError {
    case unreadable
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: "This file couldn't be opened as a PDF. It may be damaged or password-protected."
        case .copyFailed(let reason): "The PDF couldn't be copied into Open Study: \(reason)"
        }
    }
}

@MainActor
final class DocumentStore {
    static let shared = DocumentStore()

    private var cache: [String: PDFDocument] = [:]
    private var pendingSaves: [String: DispatchWorkItem] = [:]

    func url(for fileName: String) -> URL {
        AppPaths.documentsDirectory.appendingPathComponent(fileName)
    }

    func fileExists(_ document: StudyDocument) -> Bool {
        FileManager.default.fileExists(atPath: url(for: document.fileName).path)
    }

    /// Copies a user-selected PDF into the container and returns the stored file name.
    func importPDF(from source: URL) throws -> (fileName: String, title: String) {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        guard PDFDocument(url: source) != nil else { throw DocumentError.unreadable }
        let fileName = UUID().uuidString + ".pdf"
        do {
            try FileManager.default.copyItem(at: source, to: url(for: fileName))
        } catch {
            throw DocumentError.copyFailed(error.localizedDescription)
        }
        return (fileName, source.deletingPathExtension().lastPathComponent)
    }

    /// Replaces a missing file with a newly chosen one, keeping the same record.
    func relink(_ document: StudyDocument, to source: URL) throws {
        let imported = try importPDF(from: source)
        cache[document.fileName] = nil
        document.fileName = imported.fileName
    }

    func pdf(for document: StudyDocument) -> PDFDocument? {
        if let cached = cache[document.fileName] { return cached }
        guard let pdf = PDFDocument(url: url(for: document.fileName)) else { return nil }
        cache[document.fileName] = pdf
        return pdf
    }

    /// Debounced write of annotations back to disk.
    func scheduleSave(_ document: StudyDocument) {
        let name = document.fileName
        pendingSaves[name]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow(fileName: name) }
        pendingSaves[name] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func saveNow(fileName: String) {
        pendingSaves[fileName] = nil
        guard let pdf = cache[fileName] else { return }
        let target = url(for: fileName)
        let temp = target.deletingLastPathComponent().appendingPathComponent(".\(fileName).tmp")
        // Write to a temp file first so a failed write never corrupts the original.
        if pdf.write(to: temp) {
            _ = try? FileManager.default.replaceItemAt(target, withItemAt: temp)
        }
    }

    func flushAll() {
        for name in pendingSaves.keys { saveNow(fileName: name) }
    }

    func deleteFile(for document: StudyDocument) {
        cache[document.fileName] = nil
        try? FileManager.default.removeItem(at: url(for: document.fileName))
    }

    func choosePDF() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Import"
        panel.message = "Choose a PDF to add to Open Study. A copy is stored inside the app."
        return panel.runModal() == .OK ? panel.url : nil
    }
}
