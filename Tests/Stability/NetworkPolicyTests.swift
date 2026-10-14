import XCTest
@testable import Legado

final class NetworkPolicyTests: XCTestCase {
    func testHTTPSourceWithADomainNameCanLoadThroughTheAppPolicy() async throws {
        // 使用普通域名验证 ATS。CI 映射默认域名，本地可以使用已有的本机域名映射。
        let url = ProcessInfo.processInfo.environment["LEGADO_DOMAIN_FIXTURE_URL"]
            ?? "http://legado-fixture.test:8766/search"
        let host = try XCTUnwrap(URL(string: url)?.host)
        XCTAssertTrue(host.contains("."), "不能用 localhost 或裸 IP 绕过普通域名的 ATS 检查")
        XCTAssertFalse(host.allSatisfy { $0.isNumber || $0 == "." })
        let (data, response) = try await HTTPClient.shared.get(url: url, timeout: 10)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("测试书籍"))
    }
}
