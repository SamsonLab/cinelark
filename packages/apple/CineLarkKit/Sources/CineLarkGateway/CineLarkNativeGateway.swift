import Foundation

public final class CineLarkNativeGateway: Sendable {
    public let iina: IINABridgeCenter
    public let remote: RemoteGatewayCenter

    private let process: GatewayProcessShell

    public init(bundle: Bundle = .main) {
        let process = GatewayProcessShell(
            executableURL: bundle.bundleURL.appendingPathComponent(
                "Contents/Helpers/CineLarkGateway",
                isDirectory: false
            )
        )
        self.process = process
        iina = IINABridgeCenter(process: process)
        remote = RemoteGatewayCenter(process: process)
    }

    public func shutdown() async {
        await process.shutdown()
    }
}
