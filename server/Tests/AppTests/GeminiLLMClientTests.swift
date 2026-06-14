import XCTVapor
@testable import App

/// Verifies the function-calling wiring without a network call: the response
/// parser (does the model call a tool?) and the request builder (roles + tool
/// declarations). The live call is verified against the real key at deploy.
final class GeminiLLMClientTests: XCTestCase {
    func testParseFunctionCall() throws {
        let json = #"{"candidates":[{"content":{"parts":[{"functionCall":{"name":"compute_totals","args":{"tripId":"abc-123"}}}]}}]}"#
        let r = try GeminiLLMClient.parse(Data(json.utf8))
        guard case .toolCall(let name, let args) = r else { return XCTFail("expected toolCall, got \(r)") }
        XCTAssertEqual(name, "compute_totals")
        XCTAssertTrue(args.contains("abc-123"))
    }

    func testParseFinalText() throws {
        let json = #"{"candidates":[{"content":{"parts":[{"text":"You've spent ¥3520 on food."}]}}]}"#
        let r = try GeminiLLMClient.parse(Data(json.utf8))
        guard case .finalText(let text) = r else { return XCTFail("expected finalText, got \(r)") }
        XCTAssertTrue(text.contains("3520"))
    }

    func testParseEmptyFallsBack() throws {
        let r = try GeminiLLMClient.parse(Data("{}".utf8))
        guard case .finalText = r else { return XCTFail("expected finalText fallback") }
    }

    func testBuildRequestMapsRolesAndDeclaresTools() throws {
        let req = GeminiLLMClient.buildRequest(
            messages: [
                LLMMessage(role: "user", content: "how much on food?"),
                LLMMessage(role: "tool", content: #"{"total":3520}"#, toolName: "compute_totals"),
            ],
            tools: AgentService.toolSpecs
        )
        let s = String(data: try JSONEncoder().encode(req), encoding: .utf8)!
        XCTAssertTrue(s.contains("\"role\":\"user\""))
        XCTAssertTrue(s.contains("functionDeclarations"))
        XCTAssertTrue(s.contains("compute_totals"))
        XCTAssertTrue(s.contains("Tool compute_totals returned"))  // tool result fed back as text
    }
}
