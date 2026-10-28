//
//  PCChannelTests.swift
//  PlayToolsTests
//
//  PCChannel JSON-lines protocol codec (OPTIMIZATION.md phase 4).
//

import XCTest

final class PCChannelTests: XCTestCase {

    // MARK: encode/decode round trips

    func testHandshakeRoundTrip() throws {
        let message = PCChannel.Message.handshake(bundleIdentifier: "com.example.game")
        let decoded = try PCChannel.Codec.decodeLine(try PCChannel.Codec.encodeLine(message))

        XCTAssertEqual(decoded.command, PCChannel.cmdHandshake)
        XCTAssertEqual(decoded.protocolVersion, PCChannel.protocolVersion)
        XCTAssertEqual(decoded.bundleIdentifier, "com.example.game")
    }

    func testCommandRoundTrips() throws {
        let messages: [PCChannel.Message] = [
            .keymapUpdate(),
            .settingsRefresh(),
            .diagDump(),
            .logLevel("debug"),
            .reply(to: 3, isOK: false, error: "gone")
        ]
        for message in messages {
            let decoded = try PCChannel.Codec.decodeLine(try PCChannel.Codec.encodeLine(message))
            XCTAssertEqual(decoded.command, message.command)
            XCTAssertEqual(decoded.id, message.id)
            XCTAssertEqual(decoded.level, message.level)
            XCTAssertEqual(decoded.isOK, message.isOK)
            XCTAssertEqual(decoded.error, message.error)
        }
    }

    func testEncodeLineIsNewlineTerminated() throws {
        let line = try PCChannel.Codec.encodeLine(.keymapUpdate())
        XCTAssertTrue(line.hasSuffix("\n"))
        XCTAssertFalse(line.contains("\n\n"))
    }

    // MARK: forward compatibility

    func testDecodeIgnoresUnknownFields() throws {
        let json = #"{"command":"keymap.update","futureField":[1,2,3],"id":9}"#
        let decoded = try PCChannel.Codec.decodeLine(json)
        XCTAssertEqual(decoded.command, PCChannel.cmdKeymapUpdate)
        XCTAssertEqual(decoded.id, 9)
    }

    func testUnknownCommandStillDecodes() throws {
        let json = #"{"command":"some.future.command"}"#
        let decoded = try PCChannel.Codec.decodeLine(json)
        XCTAssertEqual(decoded.command, "some.future.command")
    }

    func testDecodeMissingCommandThrows() {
        XCTAssertThrowsError(try PCChannel.Codec.decodeLine(#"{"id":1}"#))
    }

    // MARK: line framing

    func testDrainLinesExtractsCompleteLinesAndKeepsPartial() {
        var buffer = #"{"command":"a"}"#
            + "\n"
            + "\n"
            + #"{"command":"b"}"#
            + "\n"
            + #"{"command":"par"#
        let lines = PCChannel.Codec.drainLines(&buffer)

        XCTAssertEqual(lines, [#"{"command":"a"}"#, #"{"command":"b"}"#])
        XCTAssertEqual(buffer, #"{"command":"par"#)

        let rest = PCChannel.Codec.drainLines(&buffer)
        XCTAssertTrue(rest.isEmpty)
        XCTAssertEqual(buffer, #"{"command":"par"#)

        buffer += #"tial"}"# + "\n"
        XCTAssertEqual(PCChannel.Codec.drainLines(&buffer), [#"{"command":"partial"}"#])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testDrainLinesOnEmptyBufferIsEmpty() {
        var buffer = ""
        XCTAssertTrue(PCChannel.Codec.drainLines(&buffer).isEmpty)
    }
}
