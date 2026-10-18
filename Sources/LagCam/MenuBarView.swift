import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if state.cameraDenied {
                warning("Camera access denied. Enable LagCam in System Settings → Privacy & Security → Camera.")
            } else if !state.status.sinkConnected {
                warning("OBS Virtual Camera not found. Install OBS, click “Start Virtual Camera” once, approve the system extension, then quit OBS.")
            }

            disconnectSection
            Divider()
            manualSection
            Divider()
            settingsSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { state.refreshCameras() }
    }

    private var header: some View {
        HStack {
            Image(systemName: state.menuBarSymbol)
                .font(.title2)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("LagCam").font(.headline)
                Text(state.status.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusDot(on: state.status.cameraRunning, label: "Cam")
            statusDot(on: state.status.sinkConnected, label: "OBS")
        }
    }

    private var disconnectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    state.fakeDisconnect()
                } label: {
                    Label("Disconnect", systemImage: "wifi.slash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(fill: .red, height: 34))

                Button {
                    state.reconnect()
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(fill: nil, height: 34))
            }

            Picker("Degrade over", selection: $state.disconnectDuration) {
                Text("15s").tag(15.0)
                Text("30s").tag(30.0)
                Text("60s").tag(60.0)
            }
            .pickerStyle(.segmented)
        }
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manual").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(Mode.allCases) { mode in
                    let selected = state.status.mode == mode && !state.status.scripted
                    Button {
                        state.setMode(mode)
                    } label: {
                        Label(mode.title, systemImage: mode.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(PillButtonStyle(fill: selected ? .accentColor : nil, height: 28))
                }
            }
            HStack {
                Text("Intensity").font(.caption)
                Slider(value: $state.intensity, in: 0.1...1)
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Camera", selection: $state.selectedCameraID) {
                ForEach(state.cameras) { camera in
                    Text(camera.name).tag(Optional(camera.id))
                }
            }
            Button {
                state.togglePreview()
            } label: {
                Label("Show preview", systemImage: "rectangle.on.rectangle")
            }
            .buttonStyle(.link)
        }
    }

    private var footer: some View {
        HStack(alignment: .top) {
            Text("⌃⌥1–4 modes · ⌃⌥D disconnect · ⌃⌥R reconnect")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { state.quit() }
                .controlSize(.small)
        }
    }

    private func statusDot(on: Bool, label: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(on ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Explicitly colored buttons: system tints are not reliably drawn inside menu-bar popovers.
private struct PillButtonStyle: ButtonStyle {
    let fill: Color?
    let height: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: fill == nil ? .regular : .semibold))
            .foregroundStyle(fill == nil ? Color.primary : Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: height / 2.6, style: .continuous)
                    .fill(fill ?? Color.primary.opacity(0.09)))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}
