//
//  PCChannelTransport.swift
//  PlayTools
//
//  Byte transport seam for the PCChannel protocol (OPTIMIZATION.md
//  phase 4). PCChannelSocketTransport is a blocking POSIX AF_UNIX
//  stream client intended to be driven from one dedicated thread.
//  Dual-compiled into PlayToolsTests.
//

import Darwin
import Foundation

protocol PCChannelTransport: AnyObject {
    /// Connect to the host. Returns false when the host socket is absent
    /// or refuses the connection.
    func open() -> Bool
    /// Send one pre-encoded protocol line. Returns false on failure.
    func send(_ line: String) -> Bool
    /// Blocking read of the next available chunk. Returns nil on EOF or
    /// error.
    func receive() -> Data?
    func close()
}

final class PCChannelSocketTransport: PCChannelTransport {
    private let path: String
    private var socketFD: Int32 = -1

    init(path: String) {
        self.path = path
    }

    deinit {
        close()
    }

    func open() -> Bool {
        close()
        let newFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard newFD >= 0 else { return false }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            Darwin.close(newFD)
            return false
        }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.copyBytes(from: pathBytes)
        }
        let status = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(newFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard status == 0 else {
            Darwin.close(newFD)
            return false
        }
        socketFD = newFD
        return true
    }

    func send(_ line: String) -> Bool {
        guard socketFD >= 0, let data = line.data(using: .utf8) else { return false }
        return data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return false }
            var sent = 0
            while sent < raw.count {
                let written = write(socketFD, base.advanced(by: sent), raw.count - sent)
                guard written > 0 else { return false }
                sent += written
            }
            return true
        }
    }

    func receive() -> Data? {
        guard socketFD >= 0 else { return nil }
        var chunk = [UInt8](repeating: 0, count: 4096)
        let received = chunk.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return -1 }
            return read(socketFD, base, raw.count)
        }
        guard received > 0 else { return nil }
        return Data(chunk[0..<received])
    }

    func close() {
        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }
    }
}
