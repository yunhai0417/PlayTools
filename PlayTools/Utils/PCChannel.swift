//
//  PCChannel.swift
//  PlayTools
//
//  JSON-lines protocol between the PlayCover host and the PlayTools runtime
//  (OPTIMIZATION.md phase 4). One JSON object per line, UTF-8, "\n"
//  delimited. The runtime is the client, the host is the server.
//  Unknown commands and unknown fields must be ignored (forward
//  compatibility), so `command` stays a plain string. Dual-compiled into
//  PlayToolsTests.
//

import Foundation

enum PCChannel {
    static let protocolVersion = 1

    // Known commands (protocol v1)
    static let cmdHandshake = "hello"             // C->S: version + bundle id
    static let cmdKeymapUpdate = "keymap.update"   // S->C: keymap plist changed
    static let cmdSettingsRefresh = "settings.refresh" // S->C: settings plist changed
    static let cmdDiagDump = "diag.dump"           // S->C: request hook status dump
    static let cmdLogLevel = "log.level"           // S->C: set runtime log level
    static let cmdReply = "reply"                  // S->C ack for a request id

    struct Message: Codable {
        var command: String
        var id: Int?
        var protocolVersion: Int?
        var bundleIdentifier: String?
        var level: String?
        var isOK: Bool?
        var error: String?

        static func handshake(bundleIdentifier: String) -> Message {
            Message(command: PCChannel.cmdHandshake,
                    protocolVersion: PCChannel.protocolVersion,
                    bundleIdentifier: bundleIdentifier)
        }

        static func keymapUpdate() -> Message {
            Message(command: PCChannel.cmdKeymapUpdate)
        }

        static func settingsRefresh() -> Message {
            Message(command: PCChannel.cmdSettingsRefresh)
        }

        static func diagDump() -> Message {
            Message(command: PCChannel.cmdDiagDump)
        }

        static func logLevel(_ level: String) -> Message {
            Message(command: PCChannel.cmdLogLevel, level: level)
        }

        static func reply(to id: Int?, isOK: Bool, error: String? = nil) -> Message {
            Message(command: PCChannel.cmdReply, id: id, isOK: isOK, error: error)
        }
    }

    enum Codec {
        static func encodeLine(_ message: Message) throws -> String {
            let data = try JSONEncoder().encode(message)
            return String(data: data, encoding: .utf8)! + "\n"
        }

        static func decodeLine(_ line: String) throws -> Message {
            guard let data = line.data(using: .utf8) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "line is not valid UTF-8"))
            }
            return try JSONDecoder().decode(Message.self, from: data)
        }

        /// Extract complete "\n"-terminated lines from `buffer`, leaving any
        /// trailing partial line in place for the next read. Empty lines are
        /// skipped.
        static func drainLines(_ buffer: inout String) -> [String] {
            var lines: [String] = []
            while let newline = buffer.firstIndex(of: "\n") {
                let line = String(buffer[buffer.startIndex..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
                if !line.isEmpty {
                    lines.append(line)
                }
            }
            return lines
        }
    }
}

extension PCChannel.Message {
    enum CodingKeys: String, CodingKey {
        case command, id, protocolVersion, bundleIdentifier, level
        case isOK = "ok"
        case error
    }
}
