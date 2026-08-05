import XCTest
@testable import VoxlyApp

final class LocalRefinerTests: XCTestCase {
    func testDetectsIntroducedAssistantResponse() {
        let source = "Create a concise code review prompt that asks whether this branch introduced the bug."
        let result = "Hey developer, here's a quick hook to kick off your code review:"

        XCTAssertTrue(LocalRefiner.looksLikeAssistantResponse(result, source: source))
    }

    func testAllowsOrdinaryRewrite() {
        let source = "Could you please create a short incident report?"
        let result = "Create a short incident report."

        XCTAssertFalse(LocalRefiner.looksLikeAssistantResponse(result, source: source))
    }

    func testAllowsAssistantStyleWordingAlreadyInSource() {
        let source = "Here is the incident report you requested."
        let result = "Here's the requested incident report."

        XCTAssertFalse(LocalRefiner.looksLikeAssistantResponse(result, source: source))
    }

    func testDetectsPortugueseDespiteMentioningEnglish() {
        let source = "Crie o commit para essas mudanças e suba o código para o GitHub. Não esqueça de fazer o commit em inglês."

        XCTAssertEqual(LocalRefiner.sourceLanguage(for: source), .portuguese)
    }

    func testRejectsPortugueseToEnglishTranslation() {
        let result = "Create a commit for these changes and push the code to GitHub. Do not forget to commit in English."

        XCTAssertTrue(LocalRefiner.changesLanguage(result, from: .portuguese))
    }

    func testAllowsPortugueseRewrite() {
        let result = "Crie o commit dessas mudanças em inglês e envie o código ao GitHub."

        XCTAssertFalse(LocalRefiner.changesLanguage(result, from: .portuguese))
    }
}