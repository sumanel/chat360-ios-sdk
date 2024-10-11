import XCTest
@testable import chat360_iosSdk

final class chat360_iosSdkTests: XCTestCase {
    func testCreateUrl_WithValidInputs() {
         // Given
         let botId = "testBotId"
         let appId = "com.chat360.demo"
         let meta: [String: String] = ["key": "value"]
         let config = Chat360Config(botId: botId, appId: appId, meta: meta)
         
         // When
         let url = config.createUrl()
         
         // Then
         XCTAssertNotNil(url, "URL should not be nil")
         XCTAssertEqual(url?.absoluteString, "https://app.chat360.io/page?h=\(botId)&store_session=1&app_id=\(appId)&is_mobile=true&mobile=1&meta=%7B%22key%22:%22value%22%7D", "URL string does not match expected format")
     }
     
     func testCreateUrl_WithStagingMode() {
         // Given
         let botId = "testBotId"
         let appId = "com.chat360.demo"
         let meta: [String: String] = ["key": "value"]
         let config = Chat360Config(botId: botId, appId: appId, isDebug: true, meta: meta)
         
         // When
         let url = config.createUrl()
         
         // Then
         XCTAssertNotNil(url, "URL should not be nil")
         XCTAssertEqual(url?.absoluteString, "https://app.gaadibaazar.in/page?h=\(botId)&store_session=1&app_id=\(appId)&is_mobile=true&mobile=1&meta=%7B%22key%22:%22value%22%7D", "URL string does not match expected format in debug mode")
     }
     
     func testCreateUrl_WithFlutter() {
         // Given
         let botId = "testBotId"
         let appId = "com.chat360.demo"
         let meta: [String: String] = ["key": "value"]
         let config = Chat360Config(botId: botId, appId: appId, flutter: true, meta: meta)
         
         // When
         let url = config.createUrl()
         
         // Then
         XCTAssertNotNil(url, "URL should not be nil")
         XCTAssertEqual(url?.absoluteString, "https://app.chat360.io/page?h=\(botId)&store_session=1&app_id=\(appId)&is_mobile=true&mobile=1&meta=%7B%22key%22:%22value%22%7D&flutter_sdk_type=ios", "URL string does not match expected format with Flutter")
     }
     
    func testCreateUrl_WithNilMeta() {
        // Given
        let botId = "testBotId"
        let appId = "com.chat360.demo"
        let config = Chat360Config(botId: botId, appId: appId, flutter: false, meta: nil)
        
        // When
        let url = config.createUrl()
        
        // Then
        XCTAssertNotNil(url, "URL should be nil when meta is nil")
        XCTAssertEqual(url?.absoluteString, "https://app.chat360.io/page?h=\(botId)&store_session=1&app_id=\(appId)&is_mobile=true&mobile=1", "URL string does not match expected format with Flutter")
    }
}
