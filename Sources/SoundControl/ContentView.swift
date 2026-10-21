import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var systemVolume: SystemVolumeController
    @EnvironmentObject private var appVolumes: AppVolumeController
    @EnvironmentObject private var launchAtLogin: LaunchAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            masterSection
            Divider()
            appsSection
            if let message = appVolumes.errorMessage ?? launchAtLogin.errorMessage {
                errorBanner(message)
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: - Sections

    private var masterSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Volumen general")
                    .font(.headline)
                Spacer()
                Text(systemVolume.deviceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            VolumeRow(
                volume: systemVolume.volume,
                isMuted: systemVolume.isMuted,
                onChange: systemVolume.setVolume,
                onToggleMute: systemVolume.toggleMute
            )
            .disabled(!systemVolume.canChangeVolume)
        }
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Aplicaciones")
                    .font(.headline)
                Spacer()
                if !appVolumes.volumes.isEmpty || !appVolumes.muted.isEmpty {
                    Button("Restablecer") { appVolumes.resetAll() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }

            if appVolumes.apps.isEmpty {
                Text("Ninguna aplicación está reproduciendo sonido.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(appVolumes.apps) { app in
                            AppRow(app: app)
                        }
                    }
                }
                .frame(maxHeight: 320)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Abrir Ajustes de privacidad") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                        NSWorkspace.shared.open(url)
                    }
                    appVolumes.dismissError()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack {
            Toggle("Abrir al iniciar sesión", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.set($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.callout)
            Spacer()
            Button("Salir") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

private struct AppRow: View {
    @EnvironmentObject private var appVolumes: AppVolumeController
    let app: AudioApp

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 26, height: 26)
                .opacity(app.isPlaying ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.callout)
                    .lineLimit(1)
                VolumeRow(
                    volume: appVolumes.volume(for: app),
                    isMuted: appVolumes.isMuted(app),
                    onChange: { appVolumes.setVolume($0, for: app) },
                    onToggleMute: { appVolumes.toggleMute(app) }
                )
            }
        }
    }
}

private struct VolumeRow: View {
    let volume: Float
    let isMuted: Bool
    let onChange: (Float) -> Void
    let onToggleMute: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleMute) {
                Image(systemName: symbol)
                    .frame(width: 18)
            }
            .buttonStyle(.borderless)
            .help(isMuted ? "Activar sonido" : "Silenciar")

            Slider(
                value: Binding(get: { Double(isMuted ? 0 : volume) }, set: { onChange(Float($0)) }),
                in: 0...1
            )
            .controlSize(.small)

            Text("\(Int(((isMuted ? 0 : volume) * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var symbol: String {
        if isMuted || volume == 0 { return "speaker.slash.fill" }
        if volume < 0.34 { return "speaker.wave.1.fill" }
        if volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
