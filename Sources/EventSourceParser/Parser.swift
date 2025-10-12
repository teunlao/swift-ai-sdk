import Foundation

public final class EventSourceParser: @unchecked Sendable {
    private let callbacks: ParserCallbacks

    private var incompleteLine: String = ""
    private var isFirstChunk: Bool = true
    private var id: String?
    private var data: String = ""
    private var eventType: String = ""
    private var prevTrailingCR: Bool = false

    public init(callbacks: ParserCallbacks) {
        self.callbacks = callbacks
    }

    public func feed(_ chunkData: Data) {
        guard let s = String(data: chunkData, encoding: .utf8) else { return }
        feed(s)
    }

    public func feed(_ newChunk: String) {
        // Strip BOM only if it is the very first character of the first chunk (anchored)
        let chunk: String
        if isFirstChunk, newChunk.unicodeScalars.first?.value == 0xFEFF {
            chunk = String(newChunk.dropFirst())
        } else {
            chunk = newChunk
        }

        var chunkToProcess = chunk
        // Handle CR at previous chunk end (spec: CR at end might be part of CRLF across chunks)
        if prevTrailingCR {
            if chunkToProcess.first == "\n" {
                // CRLF across boundary: finalize the current line and drop the LF
                parseLine(incompleteLine)
                incompleteLine.removeAll(keepingCapacity: true)
                chunkToProcess.removeFirst()
            } else {
                // Lone CR: finalize the current line
                parseLine(incompleteLine)
                incompleteLine.removeAll(keepingCapacity: true)
            }
            prevTrailingCR = false
        }

        // Now split only the new chunk; prepend nothing as incomplete was consumed if needed
        let (complete, incomplete, trailingCR) = splitLinesWithCR(chunkToProcess)
        for line in complete {
            // If there was leftover from previous feed (without trailing CR), prepend it to first line
            if !incompleteLine.isEmpty {
                let merged = incompleteLine + line
                parseLine(merged)
                incompleteLine.removeAll(keepingCapacity: true)
            } else {
                parseLine(line)
            }
        }
        // Store new incomplete (without finalization)
        if !incomplete.isEmpty {
            incompleteLine += incomplete
        }
        prevTrailingCR = trailingCR
        isFirstChunk = false
    }

    public func reset(consume: Bool = false) {
        if !incompleteLine.isEmpty && consume {
            parseLine(incompleteLine)
        }
        isFirstChunk = true
        id = nil
        data = ""
        eventType = ""
        incompleteLine = ""
        prevTrailingCR = false
    }

    private func parseLine(_ line: String) {
        if line.isEmpty {
            dispatchEvent()
            return
        }
        if line.hasPrefix(":") {
            if let onComment = callbacks.onComment {
                // Per spec: if comment starts with ": " (colon + space), remove both
                // Otherwise just remove the colon
                let offset = line.hasPrefix(": ") ? 2 : 1
                let value = String(line.dropFirst(offset))
                onComment(value)
            }
            return
        }
        if let idx = line.firstIndex(of: ":") {
            let field = String(line[..<idx])
            let nextIndex = line.index(after: idx)
            let hasSpace = nextIndex < line.endIndex && line[nextIndex] == " "
            let valueStart = hasSpace ? line.index(after: nextIndex) : nextIndex
            let value = String(line[valueStart...])
            processField(field: field, value: value, line: line)
            return
        } else {
            processField(field: line, value: "", line: line)
        }
    }

    private func processField(field: String, value: String, line: String) {
        switch field {
        case "event":
            eventType = value
        case "data":
            data += value + "\n"
        case "id":
            if !value.contains("\u{0000}") {
                id = value
            }
        case "retry":
            if !value.isEmpty && value.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }) {
                if let intVal = Int(value) { callbacks.onRetry(intVal) }
                else { callbacks.onError(ParseError(.invalidRetry(value: value, line: line))) }
            } else {
                callbacks.onError(ParseError(.invalidRetry(value: value, line: line)))
            }
        default:
            callbacks.onError(ParseError(.unknownField(field: field, value: value, line: line)))
        }
    }

    private func dispatchEvent() {
        let shouldDispatch = !data.isEmpty
        if shouldDispatch {
            var payload = data
            if payload.last == "\n" { payload.removeLast() }
            callbacks.onEvent(EventSourceMessage(id: id, event: eventType.isEmpty ? nil : eventType, data: payload))
        }
        id = nil
        data = ""
        eventType = ""
    }

    // Split lines per WHATWG spec; also returns a flag when CR is the trailing char
    private func splitLinesWithCR(_ chunk: String) -> (complete: [String], incomplete: String, trailingCR: Bool) {
        var lines: [String] = []
        var current = String()
        current.reserveCapacity(chunk.count)
        let scalars = Array(chunk.unicodeScalars)
        var i = 0
        var trailingCR = false
        while i < scalars.count {
            let v = scalars[i].value
            if v == 13 { // CR
                let next = i + 1
                if next < scalars.count {
                    if scalars[next].value == 10 { // CRLF
                        lines.append(current)
                        current.removeAll(keepingCapacity: true)
                        i += 2
                        continue
                    } else {
                        lines.append(current)
                        current.removeAll(keepingCapacity: true)
                        i += 1
                        continue
                    }
                } else {
                    // trailing CR at end of chunk — keep as incomplete (do not finalize)
                    i += 1
                    trailingCR = true
                    break
                }
            } else if v == 10 { // LF
                lines.append(current)
                current.removeAll(keepingCapacity: true)
                i += 1
                continue
            } else {
                current.unicodeScalars.append(scalars[i])
                i += 1
            }
        }
        return (lines, current, trailingCR)
    }
}
