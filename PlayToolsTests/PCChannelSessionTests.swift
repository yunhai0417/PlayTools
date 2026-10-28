//
//  PCChannelSessionTests.swift
//  PlayToolsTests
//
//  PCChannelSession chunk reassembly (OPTIMIZATION.md phase 4): byte
//  chunks -> complete messages, with split UTF-8 sequences and malformed
//  lines handled silently.
//

import XCTest

final class PCChannelSessionTests: XCTestCase {

    private func data(_ string: String) -> Data {
        Data(string.utf8)
    }

    func testCompleteMessageInOneChunk() {
        let session = PCChannelSession()
        let messages = session.appendChunk(data(#"{"command":"keymap.update"}"# + "\n"))

        XCTAssertEqual(messages.map(\.command), [PCChannel.cmdKeymapUpdate])
    }

    func testMessageWithoutNewlineIsHeldUntilTerminated() {
        let session = PCChannelSession()
        XCTAssertTrue(session.appendChunk(data(#"{"command":"keymap.update"}"#)).isEmpty)

        let messages = session.appendChunk(data("\n\n"))
        XCTAssertEqual(messages.map(\.command), [PCChannel.cmdKeymapUpdate])
    }

    func testMalformedLineIsDroppedButNeighborsDecode() {
        let session = PCChannelSession()
        let payload = #"{"command":"settings.refresh"}"#
            + "\n"
            + "not json at all"
            + "\n"
            + #"{"command":"diag.dump"}"#
            + "\n"

        let messages = session.appendChunk(data(payload))
        XCTAssertEqual(messages.map(\.command), [PCChannel.cmdSettingsRefresh, PCChannel.cmdDiagDump])
    }

    func testChunkBoundaryInsideMultibyteCharacter() {
        let session = PCChannelSession()
        let prefix = #"{"command":"log.level","level":"#
        let line = prefix + "\"デバッグ\"}\n"

        let splitAt = data(prefix).count + 2 // inside the first multibyte char
        let bytes = data(line)
        XCTAssertTrue(session.appendChunk(bytes[..<splitAt]).isEmpty)

        let messages = session.appendChunk(bytes[splitAt...])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.level, "デバッグ")
    }

    func testResetDiscardsPartialLine() {
        let session = PCChannelSession()
        XCTAssertTrue(session.appendChunk(data(#"{"command":"par"#)).isEmpty)

        session.reset()
        let messages = session.appendChunk(data(#"tial"}"# + "\n"))

        XCTAssertTrue(messages.isEmpty) // not valid JSON on its own, dropped
    }
}
