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

        XCTAssertTrue(LocalRefiner.hasUnexpectedLanguage(result, expected: .portuguese))
    }

    func testAllowsPortugueseRewrite() {
        let result = "Crie o commit dessas mudanças em inglês e envie o código ao GitHub."

        XCTAssertFalse(LocalRefiner.hasUnexpectedLanguage(result, expected: .portuguese))
    }

    func testTranslationModeExpectsEnglishOutputFromPortugueseSpeech() throws {
        let mode = DictationMode(
            name: "To English", language: .english,
            instructions: "Translate to English and rewrite concisely.", outputLanguage: .english)

        let plan = try LocalRefiner.plan(
            for: "O Luiz chegou a testar o fluxo no ambiente de desenvolvimento?",
            mode: mode, contextTokens: 2048, floor: 256)

        XCTAssertEqual(plan.sourceLanguage, .portuguese)
        XCTAssertEqual(plan.expectedOutputLanguage, .english)
        XCTAssertTrue(plan.systemPrompt.contains("Translate the source text to English"))
        XCTAssertFalse(plan.systemPrompt.contains("Do not translate"))
        XCTAssertFalse(LocalRefiner.hasUnexpectedLanguage(
            "Did Luiz test the flow in the development environment?", expected: plan.expectedOutputLanguage))
        XCTAssertTrue(LocalRefiner.hasUnexpectedLanguage(
            "O Luiz testou o fluxo no ambiente de desenvolvimento?", expected: plan.expectedOutputLanguage))
    }

    func testPreserveModeKeepsDetectedSourceLanguage() throws {
        let mode = DictationMode(
            name: "Clean text", language: .automatic,
            instructions: "Rewrite concisely.")

        let plan = try LocalRefiner.plan(
            for: "O Luiz chegou a testar o fluxo no ambiente de desenvolvimento?",
            mode: mode, contextTokens: 2048, floor: 256)

        XCTAssertEqual(plan.sourceLanguage, .portuguese)
        XCTAssertEqual(plan.expectedOutputLanguage, .portuguese)
        XCTAssertTrue(plan.systemPrompt.contains("Do not translate"))
    }

    func testLongConciseRewriteGetsAConcreteWordLimit() throws {
        let source = Array(repeating: "palavra", count: 100).joined(separator: " ")
        let mode = DictationMode(
            name: "Clean text", language: .automatic,
            instructions: "Rewrite more concisely and remove repetition.")

        let plan = try LocalRefiner.plan(for: source, mode: mode, contextTokens: 2048, floor: 256)

        XCTAssertEqual(LocalRefiner.conciseWordLimit(for: source, instructions: mode.instructions), 55)
        XCTAssertTrue(plan.userPrompt.contains("no more than 55 words"))
        XCTAssertTrue(plan.userPrompt.contains("Remove filler, false starts, repeated ideas"))
    }

    func testShortConciseRewriteIsNotForcedIntoAWordLimit() throws {
        let source = "Could you send me the updated document after lunch?"
        let mode = DictationMode(
            name: "Clean text", language: .automatic,
            instructions: "Rewrite more concisely.")

        let plan = try LocalRefiner.plan(for: source, mode: mode, contextTokens: 2048, floor: 256)

        XCTAssertNil(LocalRefiner.conciseWordLimit(for: source, instructions: mode.instructions))
        XCTAssertFalse(plan.userPrompt.contains("HARD LENGTH LIMIT"))
    }

    func testNonConciseModeDoesNotGetAWordLimit() throws {
        let source = Array(repeating: "technical detail", count: 50).joined(separator: " ")
        let mode = DictationMode(
            name: "Code/technical notes", language: .automatic,
            instructions: "Organize as a technical note and preserve every identifier.")

        let plan = try LocalRefiner.plan(for: source, mode: mode, contextTokens: 2048, floor: 256)

        XCTAssertNil(LocalRefiner.conciseWordLimit(for: source, instructions: mode.instructions))
        XCTAssertFalse(plan.userPrompt.contains("HARD LENGTH LIMIT"))
    }

    func testDedicatedTranslationPlanHasNoCopyEditingLanguageConflict() throws {
        let source = "Está faltando uma estratégia de SEO mais profunda e abrangente."

        let plan = try LocalRefiner.translationPlan(
            for: source, vocabulary: "Voxly, Whisper CLI, Llama, Services.swift",
            contextTokens: 2048, floor: 256)

        XCTAssertEqual(plan.sourceLanguage, .portuguese)
        XCTAssertEqual(plan.expectedOutputLanguage, .english)
        XCTAssertTrue(plan.systemPrompt.contains("Translate the entire source text to natural English"))
        XCTAssertTrue(plan.systemPrompt.contains("Voxly, Whisper CLI, Llama, Services.swift"))
        XCTAssertFalse(plan.systemPrompt.contains("Mentions of another language"))
        XCTAssertFalse(plan.systemPrompt.contains("Do not translate"))
    }

    func testDedicatedTranslationPlanSupportsPortugueseOutput() throws {
        let plan = try LocalRefiner.translationPlan(
            for: "Please send the updated ticket to John.", targetLanguage: .portuguese,
            contextTokens: 2048, floor: 256)

        XCTAssertEqual(plan.sourceLanguage, .english)
        XCTAssertEqual(plan.expectedOutputLanguage, .portuguese)
        XCTAssertTrue(plan.systemPrompt.contains("natural Portuguese"))
        XCTAssertTrue(plan.userPrompt.contains("to Portuguese"))
        XCTAssertFalse(plan.systemPrompt.contains("natural English"))
    }

    func testExistingModeDefaultsToPreservingInputLanguage() throws {
        let data = Data(#"{"name":"Existing mode","language":"Automatic","instructions":"Rewrite concisely."}"#.utf8)

        let mode = try JSONDecoder().decode(DictationMode.self, from: data)

        XCTAssertEqual(mode.outputLanguage, .sameAsInput)
    }

    func testExistingTranslationModeMigratesItsEnglishTarget() throws {
        let data = Data(#"{"name":"To English","language":"English","instructions":"Translate to English and rewrite more concisely using casual language."}"#.utf8)

        let mode = try JSONDecoder().decode(DictationMode.self, from: data)

        XCTAssertEqual(mode.outputLanguage, .english)
        XCTAssertEqual(mode.language, .automatic)
    }
}