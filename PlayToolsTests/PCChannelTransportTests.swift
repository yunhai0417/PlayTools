//
//  PCChannelTransportTests.swift
//  PlayToolsTests
//
//  PCChannelSocketTransport POSIX AF_UNIX behavior (OPTIMIZATION.md
//  phase 4) against an in-process listening socket.
//

import Darwin
import XCTest

final class PCChannelTransportTests: XCTestCase {

    func testOpenFailsWhenSocketDoesNotExist() {
        let missing = "/tmp/pc-test-missing-\(UUID().uuidString).sock"
        let transport = PCChannelSocketTransport(path: missing)

        XCTAssertFalse(transport.open())
    }

    func testOpenFailsWhenPathExceedsSunPathLimit() {
        // sockaddr_un.sun_path holds 104 bytes; the transport must reject a
        // longer path instead of overflowing it.
        let overlong = "/tmp/" + String(repeating: "a", count: 200) + ".sock"
        let transport = PCChannelSocketTransport(path: overlong)

        XCTAssertFalse(transport.open())
    }

    func testRoundTripOverLiveUnixDomainSocket() throws {
        let path = "/tmp/pc-test-\(UUID().uuidString).sock"
        let serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        try XCTSkipIf(serverFD < 0, "cannot create test socket")
        defer {
            unlink(path)
            Darwin.close(serverFD)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        precondition(pathBytes.count < MemoryLayout.size(ofValue: address.sun_path))
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.copyBytes(from: pathBytes)
        }
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(serverFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(bindResult, 0)
        XCTAssertEqual(listen(serverFD, 1), 0)

        let client = PCChannelSocketTransport(path: path)
        XCTAssertTrue(client.open())
        defer { client.close() }

        var peerFD = accept(serverFD, nil, nil)
        XCTAssertTrue(peerFD >= 0)
        defer {
            if peerFD >= 0 {
                Darwin.close(peerFD)
            }
        }

        // Client -> server
        let line = try PCChannel.Codec.encodeLine(.keymapUpdate())
        XCTAssertTrue(client.send(line))
        let received = Self.readLine(from: peerFD)
        XCTAssertEqual(try PCChannel.Codec.decodeLine(received).command, PCChannel.cmdKeymapUpdate)

        // Server -> client
        let reply = try PCChannel.Codec.encodeLine(.reply(to: 1, isOK: true))
        XCTAssertTrue(Self.writeAll(reply, to: peerFD))
        var incoming = Data()
        while incoming.firstIndex(of: UInt8(ascii: "\n")) == nil {
            guard let part = client.receive() else { break }
            incoming.append(part)
        }
        let incomingString = String(bytes: incoming, encoding: .utf8)!
        let decoded = try PCChannel.Codec.decodeLine(incomingString)
        XCTAssertEqual(decoded.command, PCChannel.cmdReply)
        XCTAssertEqual(decoded.isOK, true)

        // Server-side EOF propagates as nil
        Darwin.close(peerFD)
        peerFD = -1
        XCTAssertNil(client.receive())
    }

    // MARK: file-scope POSIX helpers

    private static func writeAll(_ string: String, to descriptor: Int32) -> Bool {
        let data = Data(string.utf8)
        return data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return false }
            var sent = 0
            while sent < raw.count {
                let written = write(descriptor, base.advanced(by: sent), raw.count - sent)
                guard written > 0 else { return false }
                sent += written
            }
            return true
        }
    }

    private static func readLine(from descriptor: Int32) -> String {
        var buffer = Data()
        var byte: UInt8 = 0
        while byte != UInt8(ascii: "\n") {
            guard read(descriptor, &byte, 1) == 1 else { break }
            buffer.append(byte)
        }
        return String(bytes: buffer, encoding: .utf8)!
    }
}
