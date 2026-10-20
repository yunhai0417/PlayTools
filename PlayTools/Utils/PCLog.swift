//
//  PCLog.swift
//  PlayTools
//
//  Unified os_log wrapper. Subsystem: io.playcover.PlayTools.
//  Swift: PCLog.loader.info("...")
//  ObjC:  [[PCLog loader] info:@"..."]
//

import Foundation
import os

let pcLogSubsystem = "io.playcover.PlayTools"

@objcMembers
public final class PCLogCategory: NSObject {
    private let logger: Logger

    init(category: String) {
        logger = Logger(subsystem: pcLogSubsystem, category: category)
    }

    public func debug(_ message: String) {
        logger.debug("[PC] \(message, privacy: .public)")
    }

    public func info(_ message: String) {
        logger.info("[PC] \(message, privacy: .public)")
    }

    public func error(_ message: String) {
        logger.error("[PC] \(message, privacy: .public)")
    }
}

@objcMembers
public final class PCLog: NSObject {
    public static let loader = PCLogCategory(category: "loader")
    public static let screen = PCLogCategory(category: "screen")
    public static let input = PCLogCategory(category: "input")
    public static let keychain = PCLogCategory(category: "keychain")
    public static let bypass = PCLogCategory(category: "bypass")
    public static let plugin = PCLogCategory(category: "plugin")
    public static let settings = PCLogCategory(category: "settings")
}
