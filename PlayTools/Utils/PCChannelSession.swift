//
//  PCChannelSession.swift
//  PlayTools
//
//  Session line layer for the PCChannel protocol (OPTIMIZATION.md phase 4).
//  Accumulates raw transport chunks, deframes complete "\n"-terminated
//  lines and decodes them. A chunk boundary may split a UTF-8 sequence:
//  only whole lines are converted, so no byte is ever lost. Malformed
//  lines are dropped silently (forward compatibility / silent
//  degradation). Dual-compiled into PlayToolsTests.
//

import Foundation

final class PCChannelSession {
    private var pendingBytes = Data()
    private var lineBuffer = ""

    /// Drop framing state. Call after reconnecting: a partial line left
    /// over from the previous connection is garbage.
    func reset() {
        pendingBytes.removeAll(keepingCapacity: true)
        lineBuffer = ""
    }

    /// Feed one transport chunk; returns every message it completes.
    func appendChunk(_ chunk: Data) -> [PCChannel.Message] {
        pendingBytes.append(chunk)
        if let lastNewline = pendingBytes.lastIndex(of: UInt8(ascii: "\n")) {
            let head = pendingBytes[...lastNewline]
            pendingBytes.removeSubrange(pendingBytes.startIndex...lastNewline)
            // Lossless buffering: invalid bytes become U+FFFD and fail the
            // JSON decode of their own line, not the whole chunk.
            // swiftlint:disable:next optional_data_string_conversion
            lineBuffer += String(decoding: head, as: UTF8.self)
        }
        return PCChannel.Codec.drainLines(&lineBuffer).compactMap {
            try? PCChannel.Codec.decodeLine($0)
        }
    }
}
