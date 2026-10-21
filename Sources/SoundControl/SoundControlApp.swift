import SwiftUI

@main
struct SoundControlApp: App {
    @StateObject private var systemVolume = SystemVolumeController()
    @StateObject private var appVolumes = AppVolumeController()
    @StateObject private var launchAtLogin = LaunchAtLogin()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(systemVolume)
                .environmentObject(appVolumes)
                .environmentObject(launchAtLogin)
        } label: {
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarSymbol: String {
        if systemVolume.isMuted || systemVolume.volume == 0 { return "speaker.slash.fill" }
        switch systemVolume.volume {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}
