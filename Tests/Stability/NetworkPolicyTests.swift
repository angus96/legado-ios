import XCTest
@testable import Legado

final class NetworkPolicyTests: XCTestCase {
    func testHTTPSourceWithADomainNameCanLoadThroughTheAppPolicy() async throws {
        // CI 将此测试域名指向本机的书源服务，避免依赖外部网站。
        let url = "http://legado-fixture.test:8766/search"
        let (data, response) = try await HTTPClient.shared.get(url: url, timeout: 10)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("测试书籍"))
    }
}
