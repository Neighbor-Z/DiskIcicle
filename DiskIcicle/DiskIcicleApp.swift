import SwiftUI

@main
struct AppLauncher {
    static func main() throws {
        if #available(macOS 13.0, iOS 17.0, *) {
            DiskUsageMapApp.main()
        } else {
            DiskUsageMapAppLegacy.main()
        }
    }
}

@available(macOS 13.0, iOS 17.0, *)
struct DiskUsageMapApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1000, height: 600)
        
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

struct DiskUsageMapAppLegacy: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
