//
//  GodotRuntime.swift
//
//
//  Created by Mikhail Tishin on 22.10.2023.
//

import Foundation
import libgodot
@testable import SwiftGodot

public final class GodotRuntime {
    
    static var isInitialized: Bool = false
    static var isRunning: Bool = false
    
    static var scene: SceneTree?
    
    static func run (completion: @escaping () -> Void) {
        guard !isRunning else { return }
        isInitialized = true
        isRunning = true
        runGodot (loadScene: { scene in
            self.scene = scene
            completion ()
        })
    }
    
    static func stop () {
        isRunning = false
        scene?.quit ()
    }
    
    public static func getScene () throws -> SceneTree {
        if let scene {
            return scene
        }
        throw RuntimeError.noSceneLoaded
    }
    
    enum RuntimeError: Error {
        case noSceneLoaded
    }
    
}

private var godotLibrary: OpaquePointer!
private var loadSceneCb: ((SceneTree) -> Void)?
private func embeddedExtensionInit (userData _: UnsafeMutableRawPointer?, l _: GDExtensionInitializationLevel) {}
private func embeddedExtensionDeinit (userData _: UnsafeMutableRawPointer?, l _: GDExtensionInitializationLevel) {}

private extension GodotRuntime {
    
    static func runGodot (loadScene: @escaping (SceneTree) -> ()) {
        loadSceneCb = loadScene
        
        libgodot_gdextension_bind (
            { godotGetProcAddr, libraryPtr, extensionInit in
                guard let godotGetProcAddr, let libraryPtr else {
                    return 0
                }
                let interface = LibGodotExtensionInterface(library: libraryPtr, getProcAddrFun: godotGetProcAddr)
                setExtensionInterface(interface: interface)
                godotLibrary = OpaquePointer (libraryPtr)
                extensionInit?.pointee = GDExtensionInitialization (
                    minimum_initialization_level: GDEXTENSION_INITIALIZATION_CORE,
                    userdata: libraryPtr,
                    initialize: extension_initialize,
                    deinitialize: extension_deinitialize
                )
                return 1

            },
            { ptr in
                if let loadSceneCb, let ptr {
                    loadSceneCb (SceneTree.createFrom (nativeHandle: ptr))
                }
            }
        )

        // Godot crashes in -[GodotApplicationDelegate applicationDidFinishLaunching:] if __CFBundleIdentifier isn't set.
        // Terminal sets this automatically. Xcode does not.
        // If it's set to something that isn't the main bundle ID, Godot hacks macOS into treating the process as an interactive Mac app, which is desirable.
        setenv("__CFBundleIdentifier", "SwiftGodotKit", 0)

        let args = ["SwiftGodotKit", "--headless", "--verbose"]
        withUnsafePtr (strings: args) { ptr in
            godot_main (Int32 (args.count), ptr)
            
        }
    }

    // Courtesy of GPT-4
    static func withUnsafePtr (strings: [String], callback: (UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>?) -> Void) {
        let cStrings: [UnsafeMutablePointer<Int8>?] = strings.map { string in
            // Convert Swift string to a C string (null-terminated)
            strdup (string)
        }

        // Allocate memory for the array of C string pointers
        let cStringArray = UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>.allocate (capacity: cStrings.count + 1)
        cStringArray.initialize (from: cStrings, count: cStrings.count)

        // Add a null pointer at the end of the array to indicate its end
        cStringArray[cStrings.count] = nil

        callback (cStringArray)

        for i in 0 ..< strings.count {
            free (cStringArray[i])
        }
        cStringArray.deallocate ()
    }

    
}
