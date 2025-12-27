import Testing
@testable import SwiftAISDK

@Suite("UIMessageStreamOptions defaults")
struct UIMessageStreamOptionsDefaultsTests {
    @Test("sendReasoning defaults to true (upstream parity)")
    func sendReasoningDefaultsToTrue() {
        let options = UIMessageStreamOptions<UIMessage>()
        #expect(options.sendReasoning == true)
    }
}

