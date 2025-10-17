import SwiftAISDK

private let _configureTestEnvironment: Void = {
    setWarningsLoggingDisabledForTests(true)
    globalDefaultTelemetryTracer = noopTracer
    return ()
}()
