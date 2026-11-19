//
//  CardImporter.swift
//  open-study
//
//  Text/CSV flashcard import, modelled on Anki's text import workflow:
//  choose a separator, map columns to fields, preview, then import.
//

import Foundation

enum ImportSeparator: String, CaseIterable, Identifiable {
    case auto, comma, tab, semicolon, pipe, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: "Detect automatically"
        case .comma: "Comma  ,"
        case .tab: "Tab  ⇥"
        case .semicolon: "Semicolon  ;"
        case .pipe: "Pipe  |"
        case .custom: "Custom…"
        }
    }
}

enum ImportField: String, CaseIterable, Identifiable {
    case front, back, tags, ignore
    var id: String { rawValue }
    var title: String {
        switch self {
        case .front: "Front"
        case .back: "Back"
        case .tags: "Tags"
        case .ignore: "Ignore"
        }
    }
}

enum CardImporter {
    /// Splits text into rows and fields. Supports RFC-4180 style quoting for single-character separators.
    static func parse(_ text: String, separator: String) -> [[String]] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if separator.count != 1 {
            // Multi-character separators (e.g. "::" or " - "): no quoting.
            return normalized.split(separator: "\n", omittingEmptySubsequences: false)
                .map { String($0) }
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }
                .map { $0.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespaces) } }
        }

        let sep = Character(separator)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(normalized)
        chars.append("\n")
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.append("\""); i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else if c == "\"" && field.trimmingCharacters(in: .whitespaces).isEmpty {
                field = ""
                inQuotes = true
            } else if c == sep {
                row.append(field.trimmingCharacters(in: .whitespaces)); field = ""
            } else if c == "\n" {
                row.append(field.trimmingCharacters(in: .whitespaces)); field = ""
                let isBlank = row.allSatisfy { $0.isEmpty }
                let isComment = row.first?.hasPrefix("#") ?? false
                if !isBlank && !isComment { rows.append(row) }
                row = []
            } else {
                field.append(c)
            }
            i += 1
        }
        return rows
    }

    static func detectSeparator(_ text: String) -> String {
        let lines = text.split(separator: "\n").prefix(20).map(String.init)
        let candidates: [String] = ["\t", ";", "|", ",", "::"]
        var best = "\t", bestScore = -1.0
        for c in candidates {
            let counts = lines.map { $0.components(separatedBy: c).count - 1 }
            let nonZero = counts.filter { $0 > 0 }
            guard !nonZero.isEmpty else { continue }
            // Prefer separators that appear consistently on most lines.
            let consistency = Double(nonZero.count) / Double(max(1, lines.count))
            let score = consistency * 10 - Double(Set(nonZero).count)
            if score > bestScore { bestScore = score; best = c }
        }
        return best
    }

    static func looksLikeHeader(_ row: [String]) -> Bool {
        let keys = ["front", "back", "question", "answer", "term", "definition", "tags", "prompt"]
        return row.contains { keys.contains($0.lowercased()) }
    }

    static func defaultMapping(columns: Int, header: [String]?) -> [ImportField] {
        var mapping = Array(repeating: ImportField.ignore, count: columns)
        if let header {
            for (i, name) in header.enumerated() {
                let n = name.lowercased()
                if ["front", "question", "term", "prompt"].contains(n) { mapping[i] = .front }
                else if ["back", "answer", "definition"].contains(n) { mapping[i] = .back }
                else if n == "tags" || n == "tag" { mapping[i] = .tags }
            }
            if mapping.contains(.front) && mapping.contains(.back) { return mapping }
            mapping = Array(repeating: .ignore, count: columns)
        }
        if columns > 0 { mapping[0] = .front }
        if columns > 1 { mapping[1] = .back }
        if columns > 2 { mapping[2] = .tags }
        return mapping
    }

    struct Candidate: Identifiable {
        enum Status: Equatable { case ready, duplicateInDeck, duplicateInFile, missingFront, missingBack }
        let id = UUID()
        let line: Int
        let front: String
        let back: String
        let tags: [String]
        var status: Status

        var statusText: String {
            switch status {
            case .ready: "Ready"
            case .duplicateInDeck: "Already in deck"
            case .duplicateInFile: "Repeated in file"
            case .missingFront: "Missing front"
            case .missingBack: "Missing back"
            }
        }
        var isValid: Bool { status != .missingFront && status != .missingBack }
        var isDuplicate: Bool { status == .duplicateInDeck || status == .duplicateInFile }
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func candidates(rows: [[String]], mapping: [ImportField], existingFronts: Set<String>) -> [Candidate] {
        var seen = Set<String>()
        var result: [Candidate] = []
        for (index, row) in rows.enumerated() {
            func value(_ field: ImportField) -> String {
                mapping.enumerated()
                    .filter { $0.element == field && $0.offset < row.count }
                    .map { row[$0.offset] }
                    .filter { !$0.isEmpty }
                    .joined(separator: field == .tags ? " " : "\n")
            }
            let front = value(.front), back = value(.back)
            let tags = value(.tags).split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
            var status: Candidate.Status = .ready
            let key = normalize(front)
            if front.isEmpty { status = .missingFront }
            else if back.isEmpty { status = .missingBack }
            else if existingFronts.contains(key) { status = .duplicateInDeck }
            else if seen.contains(key) { status = .duplicateInFile }
            if !front.isEmpty { seen.insert(key) }
            result.append(Candidate(line: index + 1, front: front, back: back, tags: tags, status: status))
        }
        return result
    }
}
