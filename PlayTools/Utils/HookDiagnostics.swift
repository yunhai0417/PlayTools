//
//  HookDiagnostics.swift
//  PlayTools
//
//  Hook status registry + crash-time dump (OPTIMIZATION.md 0.3).
//  Records every swizzle installation result and, on crash, writes a
//  snapshot to ~/Library/Containers/io.playcover.PlayCover/Logs/<bundleId>-hooks.txt
//

import Foundation
import Darwin

// MARK: - Registry

@objcMembers
public final class HookStatusRegistry: NSObject {
    public static let shared = HookStatusRegistry()

    struct Entry {
        let target: String
        let selector: String
        let replacement: String
        let result: String
        let detail: String
    }

    private var entries: [Entry] = []
    private let lock = NSLock()

    // Results
    static let resultApplied = "applied"
    static let resultFailed = "failed"

    private override init() {
        super.init()
    }

    @objc(recordTarget:selector:replacement:result:detail:)
    public func record(target: String, selector: String, replacement: String,
                       result: String, detail: String?) {
        lock.lock()
        entries.append(Entry(target: target, selector: selector,
                             replacement: replacement, result: result,
                             detail: detail ?? ""))
        HookDiagnostics.refreshCrashSnapshot()
        lock.unlock()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    func snapshotText() -> String {
        lock.lock()
        defer { lock.unlock() }
        var lines: [String] = []
        lines.append("PlayTools hook status snapshot")
        lines.append("date: \(Date())")
        lines.append("safeMode: \(PlaySettings.shared.safeMode)")
        lines.append("total hooks recorded: \(entries.count)")
        let failedCount = entries.filter { $0.result != "applied" }.count
        lines.append("non-applied: \(failedCount)")
        lines.append("---")
        for entry in entries {
            let detail = entry.detail.isEmpty ? "" : " (\(entry.detail))"
            lines.append("[\(entry.result)] \(entry.target) -\(entry.selector) -> \(entry.replacement)\(detail)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Crash dump

@objcMembers
public final class HookDiagnostics: NSObject {

    // Globals accessed by the signal handler. Kept as plain bytes so the
    // handler can stay (mostly) async-signal-safe: open/write/close only.
    private static var snapshotBytes: [UInt8] = []
    private static var logPathBytes: [CChar] = []

    static var logDirectory: String {
        "/Users/\(NSUserName())/Library/Containers/io.playcover.PlayCover/Logs"
    }

    public static func crashLogPath() -> String {
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        return logDirectory + "/\(bundleId)-hooks.txt"
    }

    /// Installs NSException + fatal signal handlers that dump the registry.
    public static func installCrashHandlers() {
        try? FileManager.default.createDirectory(atPath: logDirectory,
                                                 withIntermediateDirectories: true)
        refreshCrashSnapshot()
        let path = crashLogPath()
        logPathBytes = path.cString(using: .utf8) ?? []

        NSSetUncaughtExceptionHandler { _ in
            HookDiagnostics.writeCrashSnapshot()
        }

        var action = sigaction()
        action.__sigaction_u.__sa_handler = ptSignalHandler
        sigemptyset(&action.sa_mask)
        action.sa_flags = 0
        for sig in [SIGSEGV, SIGABRT, SIGBUS, SIGILL] {
            sigaction(sig, &action, nil)
        }
        PCLog.loader.info("Hook diagnostics installed, crash log: \(path)")
    }

    /// Re-renders the bytes the signal handler will write. Called on every
    /// registry record (startup only, negligible cost).
    static func refreshCrashSnapshot() {
        let text = HookStatusRegistry.shared.snapshotText() + "\n"
        snapshotBytes = Array(text.utf8)
    }

    /// Manual dump from the in-game Debug menu.
    public static func exportSnapshot() {
        let path = logDirectory + "/\(Bundle.main.bundleIdentifier ?? "unknown")-hooks-manual.txt"
        try? FileManager.default.createDirectory(atPath: logDirectory,
                                                 withIntermediateDirectories: true)
        do {
            try HookStatusRegistry.shared.snapshotText().write(toFile: path, atomically: true,
                                                               encoding: .utf8)
            Toast.showHint(title: "Hook status exported: \(path)")
            PCLog.loader.info("Hook status exported to \(path)")
        } catch {
            Toast.showHint(title: "Export failed: \(error.localizedDescription)")
            PCLog.loader.error("Hook status export failed: \(error.localizedDescription)")
        }
    }

    static func writeCrashSnapshot() {
        let fileDescriptor = open(logPathBytes, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
        guard fileDescriptor >= 0 else { return }
        snapshotBytes.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress, buffer.count > 0 {
                _ = write(fileDescriptor, base, buffer.count)
            }
        }
        close(fileDescriptor)
    }
}

/// Top-level C handler: dump snapshot, then die with default disposition.
private func ptSignalHandler(_ sig: Int32) {
    HookDiagnostics.writeCrashSnapshot()
    signal(sig, SIG_DFL)
    raise(sig)
}
