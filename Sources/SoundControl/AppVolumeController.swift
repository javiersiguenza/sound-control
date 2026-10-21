import AppKit
import CoreAudio
import Foundation

struct AudioApp: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: NSImage
    var processObjectIDs: [AudioObjectID]
    var isPlaying: Bool

    static func == (lhs: AudioApp, rhs: AudioApp) -> Bool {
        lhs.id == rhs.id && lhs.processObjectIDs == rhs.processObjectIDs && lhs.isPlaying == rhs.isPlaying
    }
}

/// Discovers the processes that output audio and manages a tap per app
/// whenever its volume differs from 100 %.
@MainActor
final class AppVolumeController: ObservableObject {
    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var volumes: [String: Float]
    @Published private(set) var muted: Set<String>
    @Published private(set) var errorMessage: String?

    private var taps: [String: ProcessTap] = [:]
    private var listeners: [PropertyListener] = []
    private var timer: Timer?
    private var outputDeviceUID: String?
    private let defaults = UserDefaults.standard

    private static let volumesKey = "appVolumes"
    private static let mutedKey = "mutedApps"

    init() {
        volumes = (defaults.dictionary(forKey: Self.volumesKey) as? [String: Float]) ?? [:]
        muted = Set(defaults.stringArray(forKey: Self.mutedKey) ?? [])
        outputDeviceUID = AudioObjectID.defaultOutputDevice().deviceUID

        let system = AudioObjectID.system
        listeners = [
            PropertyListener(objectID: system, address: system.address(kAudioHardwarePropertyProcessObjectList)) { [weak self] in
                Task { @MainActor in self?.refresh() }
            },
            PropertyListener(objectID: system, address: system.address(kAudioHardwarePropertyDefaultOutputDevice)) { [weak self] in
                Task { @MainActor in self?.outputDeviceChanged() }
            }
        ].compactMap { $0 }

        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func volume(for app: AudioApp) -> Float { volumes[app.id] ?? 1 }
    func isMuted(_ app: AudioApp) -> Bool { muted.contains(app.id) }

    func setVolume(_ volume: Float, for app: AudioApp) {
        let volume = min(max(volume, 0), 1)
        if volume >= 0.999 {
            volumes.removeValue(forKey: app.id)
        } else {
            volumes[app.id] = volume
        }
        if volume > 0 { muted.remove(app.id) }
        persist()
        apply(app)
    }

    func toggleMute(_ app: AudioApp) {
        if muted.contains(app.id) {
            muted.remove(app.id)
        } else {
            muted.insert(app.id)
        }
        persist()
        apply(app)
    }

    func resetAll() {
        volumes.removeAll()
        muted.removeAll()
        persist()
        apps.forEach(apply)
    }

    func dismissError() { errorMessage = nil }

    // MARK: - Discovery

    func refresh() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var grouped: [String: AudioApp] = [:]

        for objectID in AudioObjectID.system.readObjectList(AudioObjectID.system.address(kAudioHardwarePropertyProcessObjectList)) {
            guard let pid = try? objectID.read(objectID.address(kAudioProcessPropertyPID), initial: pid_t(-1)),
                  pid > 0, pid != ownPID,
                  let identity = AppIdentity.resolve(pid: pid) else { continue }

            let isRunning = ((try? objectID.read(objectID.address(kAudioProcessPropertyIsRunningOutput), initial: UInt32(0))) ?? 0) != 0

            if var existing = grouped[identity.id] {
                existing.processObjectIDs.append(objectID)
                existing.isPlaying = existing.isPlaying || isRunning
                grouped[identity.id] = existing
            } else {
                grouped[identity.id] = AudioApp(
                    id: identity.id,
                    name: identity.name,
                    icon: identity.icon,
                    processObjectIDs: [objectID],
                    isPlaying: isRunning
                )
            }
        }

        // Show apps that are playing, plus the ones the user has adjusted that are still alive.
        let visible = grouped.values
            .map { app -> AudioApp in
                var app = app
                app.processObjectIDs.sort()
                return app
            }
            .filter { $0.isPlaying || volumes[$0.id] != nil || muted.contains($0.id) || taps[$0.id] != nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if visible != apps { apps = visible }

        // Drop taps whose app no longer exists.
        for id in taps.keys where grouped[id] == nil {
            taps.removeValue(forKey: id)?.invalidate()
        }
        visible.forEach(apply)
    }

    private func outputDeviceChanged() {
        outputDeviceUID = AudioObjectID.defaultOutputDevice().deviceUID
        for tap in taps.values { tap.invalidate() }
        taps.removeAll()
        apps.forEach(apply)
    }

    // MARK: - Taps

    private func apply(_ app: AudioApp) {
        let gain: Float = muted.contains(app.id) ? 0 : (volumes[app.id] ?? 1)

        guard gain < 0.999 else {
            taps.removeValue(forKey: app.id)?.invalidate()
            return
        }

        if let tap = taps[app.id],
           tap.processObjectIDs == app.processObjectIDs,
           tap.outputDeviceUID == outputDeviceUID {
            tap.gain = gain
            return
        }

        taps.removeValue(forKey: app.id)?.invalidate()
        guard let outputDeviceUID else { return }

        do {
            taps[app.id] = try ProcessTap(processObjectIDs: app.processObjectIDs, outputDeviceUID: outputDeviceUID, gain: gain)
            errorMessage = nil
        } catch {
            errorMessage = "No se pudo controlar \(app.name). Comprueba el permiso de grabación de audio del sistema."
        }
    }

    private func persist() {
        defaults.set(volumes, forKey: Self.volumesKey)
        defaults.set(Array(muted), forKey: Self.mutedKey)
    }
}

/// Maps a process to the user-facing app it belongs to (helpers are grouped under their parent .app).
struct AppIdentity {
    let id: String
    let name: String
    let icon: NSImage

    private static var cache: [pid_t: AppIdentity] = [:]

    static func resolve(pid: pid_t) -> AppIdentity? {
        if let cached = cache[pid] { return cached }

        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let executablePath = String(cString: buffer)
        let components = executablePath.split(separator: "/", omittingEmptySubsequences: false)

        let identity: AppIdentity
        if let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) {
            let appPath = components[...appIndex].joined(separator: "/")
            let bundle = Bundle(path: appPath)
            let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? String(components[appIndex].dropLast(4))
            identity = AppIdentity(
                id: bundle?.bundleIdentifier ?? appPath,
                name: displayName,
                icon: NSWorkspace.shared.icon(forFile: appPath)
            )
        } else {
            identity = AppIdentity(
                id: executablePath,
                name: (executablePath as NSString).lastPathComponent,
                icon: NSWorkspace.shared.icon(forFile: executablePath)
            )
        }

        cache[pid] = identity
        return identity
    }
}
