//
//  PCChannelClient.swift
//  PlayTools
//
//  Runtime-side PCChannel client (OPTIMIZATION.md phase 4). Connects to
//  the PlayCover host over a Unix domain socket, sends the version
//  handshake and dispatches host commands to registered handlers.
//  Failure is always silent: without a host, connect attempts back off
//  and give up, and the runtime behaves exactly as before.
//

import Foundation

final class PCChannelClient {
    static let shared = PCChannelClient()

    private static let reconnectDelays: [TimeInterval] = [0.5, 1, 2, 4, 8]
    private static let workerName = "io.playcover.PlayTools.pcchannel"

    private let controlQueue = DispatchQueue(label: "io.playcover.PlayTools.pcchannel.control")
    private let session = PCChannelSession()
    private let transportFactory: () -> PCChannelTransport
    private let bundleIdentifierProvider: () -> String
    private var handlers: [String: (PCChannel.Message) -> Void] = [:]
    private var started = false

    init(transportFactory: (() -> PCChannelTransport)? = nil,
         bundleIdentifierProvider: (() -> String)? = nil) {
        self.transportFactory = transportFactory
            ?? { PCChannelSocketTransport(path: PCChannelClient.defaultSocketPath()) }
        self.bundleIdentifierProvider = bundleIdentifierProvider
            ?? { Bundle.main.bundleIdentifier ?? "unknown" }
    }

    /// Socket path convention shared with the PlayCover host server.
    static func defaultSocketPath() -> String {
        let identifier = Bundle.main.bundleIdentifier ?? "unknown"
        return "/tmp/PlayCover/PC-\(identifier).sock"
    }

    /// Register (or, with nil, remove) the handler for one command.
    /// Unknown commands are ignored, per protocol.
    func setHandler(for command: String, handler: ((PCChannel.Message) -> Void)?) {
        controlQueue.sync {
            handlers[command] = handler
        }
    }

    /// Start the worker thread once. Safe to call repeatedly.
    func start() {
        controlQueue.sync {
            guard !started else { return }
            started = true
            let worker = Thread { [weak self] in
                self?.runWorker()
            }
            worker.name = PCChannelClient.workerName
            worker.start()
        }
    }

    private func runWorker() {
        var attempt = 0
        while !Thread.current.isCancelled {
            let transport = transportFactory()
            guard transport.open() else {
                guard attempt < PCChannelClient.reconnectDelays.count else {
                    PCLog.channel.debug("host channel unavailable; giving up")
                    return
                }
                Thread.sleep(forTimeInterval: PCChannelClient.reconnectDelays[attempt])
                attempt += 1
                continue
            }
            attempt = 0
            session.reset()
            guard let hello = try? PCChannel.Codec.encodeLine(
                      .handshake(bundleIdentifier: bundleIdentifierProvider())),
                  transport.send(hello) else {
                transport.close()
                continue
            }
            PCLog.channel.info("host channel connected")
            serve(transport: transport)
            transport.close()
            PCLog.channel.debug("host channel closed; reconnecting")
        }
    }

    private func serve(transport: PCChannelTransport) {
        while true {
            guard let chunk = transport.receive() else { return }
            for message in session.appendChunk(chunk) {
                dispatch(message)
            }
        }
    }

    private func dispatch(_ message: PCChannel.Message) {
        let handler = controlQueue.sync { handlers[message.command] }
        if let handler = handler {
            handler(message)
        } else {
            PCLog.channel.debug("ignoring command \(message.command)")
        }
    }
}
