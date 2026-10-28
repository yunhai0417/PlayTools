//
//  PCChannelClientTests.swift
//  PlayToolsTests
//
//  PCChannelClient plumbing (OPTIMIZATION.md phase 4) driven by a
//  scripted transport: handshake is sent, host messages are dispatched
//  to handlers, unknown commands never reach them.
//

import XCTest

final class PCChannelClientTests: XCTestCase {

    private final class ScriptedTransport: PCChannelTransport {
        var sentLines: [String] = []
        private var incoming: [Data]
        private var openResults: [Bool]

        init(incoming: [Data], openResults: [Bool] = [true]) {
            self.incoming = incoming
            self.openResults = openResults
        }

        func open() -> Bool {
            openResults.isEmpty ? false : openResults.removeFirst()
        }

        func send(_ line: String) -> Bool {
            sentLines.append(line)
            return true
        }

        func receive() -> Data? {
            incoming.isEmpty ? nil : incoming.removeFirst()
        }

        func close() {}
    }

    private func lineData(_ message: PCChannel.Message) -> Data {
        guard let line = try? PCChannel.Codec.encodeLine(message) else {
            preconditionFailure("encodeLine cannot fail for builtin messages")
        }
        return Data(line.utf8)
    }

    func testSendsHandshakeThenDispatchesCommand() {
        let transport = ScriptedTransport(incoming: [lineData(.keymapUpdate())])
        let client = PCChannelClient(transportFactory: { transport },
                                     bundleIdentifierProvider: { "com.example.game" })
        let dispatched = expectation(description: "handler invoked")

        client.setHandler(for: PCChannel.cmdKeymapUpdate) { message in
            XCTAssertEqual(message.command, PCChannel.cmdKeymapUpdate)
            dispatched.fulfill()
        }
        client.start()

        wait(for: [dispatched], timeout: 2.0)
        XCTAssertEqual(transport.sentLines.count, 1)
        let hello = try? PCChannel.Codec.decodeLine(transport.sentLines[0])
        XCTAssertEqual(hello?.command, PCChannel.cmdHandshake)
        XCTAssertEqual(hello?.protocolVersion, PCChannel.protocolVersion)
        XCTAssertEqual(hello?.bundleIdentifier, "com.example.game")
    }

    func testMultipleMessagesInOneChunkDispatchInOrder() {
        let chunk = lineData(.keymapUpdate()) + lineData(.diagDump())
        let transport = ScriptedTransport(incoming: [chunk])
        let client = PCChannelClient(transportFactory: { transport },
                                     bundleIdentifierProvider: { "com.example.game" })
        var commands: [String] = []
        let second = expectation(description: "second command dispatched")

        client.setHandler(for: PCChannel.cmdKeymapUpdate) { _ in
            commands.append(PCChannel.cmdKeymapUpdate)
        }
        client.setHandler(for: PCChannel.cmdDiagDump) { _ in
            commands.append(PCChannel.cmdDiagDump)
            second.fulfill()
        }
        client.start()

        wait(for: [second], timeout: 2.0)
        XCTAssertEqual(commands, [PCChannel.cmdKeymapUpdate, PCChannel.cmdDiagDump])
    }

    func testUnknownCommandDoesNotReachHandlers() {
        let unknown = #"{"command":"some.future.command"}"#
        let transport = ScriptedTransport(incoming: [Data((unknown + "\n").utf8)])
        let client = PCChannelClient(transportFactory: { transport },
                                     bundleIdentifierProvider: { "com.example.game" })
        let handshakeOnly = expectation(description: "handshake sent")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            handshakeOnly.fulfill()
        }

        client.setHandler(for: PCChannel.cmdKeymapUpdate) { _ in
            XCTFail("keymap handler must not run for unknown commands")
        }
        client.start()

        wait(for: [handshakeOnly], timeout: 2.0)
        XCTAssertEqual(transport.sentLines.count, 1) // just the handshake
    }
}
