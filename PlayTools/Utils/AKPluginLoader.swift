//
//  AKPluginLoader.swift
//  PlayTools
//
//  Created by Isaac Marovitz on 13/09/2022.
//

import Foundation

class AKInterface {
    public static var shared: Plugin?

    public static func initialize() {
        shared = loadPlugin()
    }

    private static func loadPlugin() -> Plugin? {
        // 1. Form the plugin's bundle URL
        guard let bundleURL = Bundle.main.builtInPlugInsURL?
                                    .appendingPathComponent("AKInterface")
                                    .appendingPathExtension("bundle") else {
            PCLog.plugin.error("AKInterface: builtInPlugInsURL unavailable")
            return nil
        }

        // 2. Create a bundle instance with the plugin URL
        guard let bundle = Bundle(url: bundleURL) else {
            PCLog.plugin.error("AKInterface: bundle not found at \(bundleURL.path)")
            return nil
        }

        // 3. Load the bundle and our plugin class
        guard let pluginClass = bundle.principalClass as? Plugin.Type else {
            PCLog.plugin.error("AKInterface: principalClass does not conform to Plugin")
            return nil
        }

        // 4. Create an instance of the plugin class
        return pluginClass.init()
    }
}
