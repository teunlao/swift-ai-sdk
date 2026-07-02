import Testing
@testable import AISDKProviderUtils

@Suite("validateDownloadUrl")
struct ValidateDownloadURLTests {
    @Test("allows public HTTP, HTTPS, public IP, ports, and data URLs")
    func allowsPublicDownloadURLs() throws {
        try validateDownloadUrl("https://example.com/image.png")
        try validateDownloadUrl("http://example.com/image.png")
        try validateDownloadUrl("https://203.0.113.1/file")
        try validateDownloadUrl("https://example.com:8080/file")
        try validateDownloadUrl("data:text/plain;base64,aGVsbG8=")
        try validateDownloadUrl("https://example.com./image.png")
        try validateDownloadUrl("http://[2001:db8::1]/file")
    }

    @Test("blocks unsafe schemes and malformed URLs")
    func blocksUnsafeSchemesAndMalformedURLs() {
        expectDownloadURLBlocked("file:///etc/passwd")
        expectDownloadURLBlocked("ftp://example.com/file")
        expectDownloadURLBlocked("javascript:alert(1)")
        expectDownloadURLBlocked("not-a-url")
    }

    @Test("blocks localhost and local hostnames including trailing dots")
    func blocksLocalHostnames() {
        expectDownloadURLBlocked("http://localhost/file")
        expectDownloadURLBlocked("http://localhost:3000/file")
        expectDownloadURLBlocked("http://localhost./file")
        expectDownloadURLBlocked("http://myhost.local/file")
        expectDownloadURLBlocked("http://myhost.local./file")
        expectDownloadURLBlocked("http://app.localhost/file")
        expectDownloadURLBlocked("http://app.localhost./file")
    }

    @Test("blocks private and reserved IPv4 ranges")
    func blocksPrivateIPv4Ranges() {
        [
            "http://0.0.0.0/file",
            "http://10.0.0.1/file",
            "http://100.64.0.1/file",
            "http://100.127.255.255/file",
            "http://127.0.0.1/file",
            "http://127.255.0.1/file",
            "http://169.254.169.254/latest/meta-data/",
            "http://172.16.0.1/file",
            "http://172.31.255.255/file",
            "http://192.0.0.1/file",
            "http://192.168.1.1/file",
            "http://198.18.0.1/file",
            "http://198.19.255.255/file",
            "http://240.0.0.1/file",
            "http://255.255.255.255/file",
        ].forEach(expectDownloadURLBlocked)
    }

    @Test("allows adjacent public IPv4 ranges")
    func allowsAdjacentPublicIPv4Ranges() throws {
        try validateDownloadUrl("http://100.63.0.1/file")
        try validateDownloadUrl("http://100.128.0.1/file")
        try validateDownloadUrl("http://172.15.0.1/file")
        try validateDownloadUrl("http://172.32.0.1/file")
    }

    @Test("blocks numeric IPv4 bypass notations")
    func blocksNumericIPv4BypassNotations() {
        expectDownloadURLBlocked("http://2130706433/file")
        expectDownloadURLBlocked("http://0x7f000001/file")
        expectDownloadURLBlocked("http://0177.0.0.1/file")
    }

    @Test("blocks private IPv6 ranges and embedded private IPv4")
    func blocksPrivateIPv6Ranges() {
        [
            "http://[::1]/file",
            "http://[::]/file",
            "http://[fc00::1]/file",
            "http://[fd12::1]/file",
            "http://[fe80::1]/file",
            "http://[fec0::1]/file",
            "http://[ff02::1]/file",
            "http://[::ffff:127.0.0.1]/file",
            "http://[::ffff:10.0.0.1]/file",
            "http://[::ffff:169.254.169.254]/file",
            "http://[::127.0.0.1]/file",
            "http://[::ffff:0:127.0.0.1]/file",
            "http://[64:ff9b::127.0.0.1]/file",
            "http://[64:ff9b::169.254.169.254]/file",
            "http://[64:ff9b:1::169.254.169.254]/file",
        ].forEach(expectDownloadURLBlocked)
    }

    @Test("allows IPv6 forms with public embedded IPv4")
    func allowsPublicEmbeddedIPv4InIPv6() throws {
        try validateDownloadUrl("http://[::ffff:203.0.113.1]/file")
        try validateDownloadUrl("http://[64:ff9b::203.0.113.1]/file")
    }

    private func expectDownloadURLBlocked(_ url: String) {
        do {
            try validateDownloadUrl(url)
            Issue.record("Expected \(url) to be blocked")
        } catch let error as DownloadError {
            #expect(error.url == url)
        } catch {
            Issue.record("Expected DownloadError for \(url), got \(error)")
        }
    }
}
