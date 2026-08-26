import CineLarkRemote
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct RemoteSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var remote: RemoteCoordinator
    @State private var presentationID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            Divider()
            content
            Divider()
            pairedDevices
        }
        .padding(28)
        .frame(width: 640, height: 680)
        .task {
            if remote.pairingDisplay == nil {
                await remote.beginPairing()
            }
        }
        .onAppear {
            remote.registerPanelPresentation(id: presentationID) {
                dismiss()
            }
        }
        .onDisappear {
            remote.unregisterPanelPresentation(id: presentationID)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text("CineLark Remote")
                    .font(.title2.bold())
                Text(statusText)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private var content: some View {
        if remote.status == .failed {
            ContentUnavailableView(
                "Remote Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("CineLark could not start its secure Remote gateway.")
            )
            Button("Retry") {
                Task {
                    await remote.start()
                    await remote.beginPairing()
                }
            }
        } else if let pairing = remote.pairingDisplay,
           let image = QRCode.image(for: pairing.payload) {
            HStack(alignment: .top, spacing: 28) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 260, height: 260)
                    .accessibilityLabel("CineLark Remote pairing code")

                VStack(alignment: .leading, spacing: 14) {
                    Label("Scan with CineLark Remote", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                    Text("The code contains a short-lived pairing secret. Approve the phone below to finish pairing.")
                        .foregroundStyle(.secondary)
                    Text("Expires \(pairing.expiresAt.formatted(date: .omitted, time: .standard))")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if remote.pendingPairings.isEmpty {
                        ProgressView("Waiting for a phone…")
                            .controlSize(.small)
                    } else {
                        ForEach(remote.pendingPairings) { request in
                            pendingPairing(request)
                        }
                    }

                    Spacer()
                    Button("Generate New Code") {
                        Task { await remote.beginPairing() }
                    }
                }
            }
        } else {
            ProgressView("Preparing secure pairing…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func pendingPairing(_ request: RemotePairingRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(request.deviceName, systemImage: "iphone")
                .font(.headline)
            HStack {
                Button("Reject", role: .destructive) {
                    Task { await remote.reject(request) }
                }
                Button("Approve") {
                    Task { await remote.approve(request) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }

    private var pairedDevices: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paired Devices")
                .font(.headline)
            if remote.pairedDevices.isEmpty {
                Text("No phones paired yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(remote.pairedDevices) { device in
                    HStack {
                        Image(systemName: "iphone")
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text(remote.connectedDeviceIDs.contains(device.id) ? "Connected" : "Offline")
                                .font(.caption)
                                .foregroundStyle(
                                    remote.connectedDeviceIDs.contains(device.id) ? .green : .secondary
                                )
                        }
                        Spacer()
                        Button("Forget", role: .destructive) {
                            Task { await remote.revoke(device) }
                        }
                    }
                }
            }
        }
    }

    private var statusText: String {
        switch remote.status {
        case .stopped: "Stopped"
        case .starting: "Starting secure gateway…"
        case .ready(let port): "Available on this network · port \(port)"
        case .failed: "Gateway unavailable"
        }
    }
}

private enum QRCode {
    static func image(for payload: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let image = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
