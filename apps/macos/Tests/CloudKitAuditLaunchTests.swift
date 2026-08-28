import Foundation
import Testing

@testable import CineLark

struct CloudKitAuditLaunchTests {
    @Test("Audit launch requests require an absolute output and bounded settle time")
    func requestParsing() {
        let request = CloudKitAuditLaunchRequest(environment: [
            CloudKitAuditLaunchRequest.outputKey: "/tmp/cinelark-audit.json",
            CloudKitAuditLaunchRequest.settleSecondsKey: "45"
        ])
        #expect(request?.outputURL.path == "/tmp/cinelark-audit.json")
        #expect(request?.settleSeconds == 45)

        #expect(CloudKitAuditLaunchRequest(environment: [:]) == nil)
        #expect(CloudKitAuditLaunchRequest(environment: [
            CloudKitAuditLaunchRequest.outputKey: "relative.json"
        ]) == nil)
        #expect(CloudKitAuditLaunchRequest(environment: [
            CloudKitAuditLaunchRequest.outputKey: "/tmp/audit.json",
            CloudKitAuditLaunchRequest.settleSecondsKey: "301"
        ]) == nil)
    }
}
