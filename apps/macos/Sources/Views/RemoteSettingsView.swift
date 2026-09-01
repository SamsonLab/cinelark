import CineLarkRemote
import ComposableArchitecture
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct RemoteSettingsView: View {
    @Bindable var store: StoreOf<RemoteFeature>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                CineLarkSettingsPageHeader(
                    title: "CineLark Remote",
                    subtitle: statusText,
                    systemImage: "iphone.and.arrow.forward"
                )

                CineLarkSettingsCard(
                    "Pair a Device",
                    subtitle: "Pairing secrets are short-lived and require approval on this Mac.",
                    systemImage: "qrcode.viewfinder"
                ) {
                    content
                }

                CineLarkSettingsCard(
                    "Paired Devices",
                    systemImage: "iphone.gen3"
                ) {
                    pairedDevices
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(CineLarkPageBackground())
        .task {
            store.send(.view(.settingsAppeared))
        }
        .onDisappear {
            store.send(.view(.settingsDisappeared))
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.status == .failed {
            ContentUnavailableView(
                "Remote Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("CineLark could not start its secure Remote gateway.")
            )
            Button("Retry") {
                store.send(.view(.retry))
            }
        } else if let pairing = store.pairingDisplay,
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

                    if store.pendingPairings.isEmpty {
                        ProgressView("Waiting for a phone…")
                            .controlSize(.small)
                    } else {
                        ForEach(store.pendingPairings) { request in
                            pendingPairing(request)
                        }
                    }

                    Spacer()
                    Button("Generate New Code") {
                        store.send(.view(.generateCode))
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
                    store.send(.view(.reject(request)))
                }
                Button("Approve") {
                    store.send(.view(.approve(request)))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }

    private var pairedDevices: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.pairedDevices.isEmpty {
                Text("No phones paired yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.pairedDevices) { device in
                    HStack {
                        Image(systemName: "iphone")
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text(store.connectedDeviceIDs.contains(device.id) ? "Connected" : "Offline")
                                .font(.caption)
                                .foregroundStyle(
                                    store.connectedDeviceIDs.contains(device.id) ? .green : .secondary
                                )
                        }
                        Spacer()
                        Button("Forget", role: .destructive) {
                            store.send(.view(.revoke(device)))
                        }
                    }
                }
            }
        }
    }

    private var statusText: String {
        switch store.status {
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
