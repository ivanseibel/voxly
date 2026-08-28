import XCTest
@testable import VoxlyApp

final class RefinementBudgetTests: XCTestCase {
    private let mode = DictationMode(
        name: "Clean text", language: .automatic,
        instructions: "Remove filler words and organize text without changing meaning or facts.")
    private let contextTokens = 2048
    private let floor = 256

    private func sentence(repeated count: Int) -> String {
        Array(repeating: "we shipped the migration yesterday and the team reviewed every step of it", count: count)
            .joined(separator: ". ")
    }

    private func plan(for raw: String) throws -> RefinementPlan {
        try LocalRefiner.plan(for: raw, mode: mode, contextTokens: contextTokens, floor: floor)
    }

    func testShortInputUsesConfiguredFloor() throws {
        let budget = try plan(for: "i think we should like ship it tomorrow ok").budget

        XCTAssertEqual(budget.outputTokens, floor)
    }

    func testMediumInputGetsBudgetAboveFloor() throws {
        let raw = sentence(repeated: 14)  // ~1000 characters
        let budget = try plan(for: raw).budget

        XCTAssertGreaterThan(budget.outputTokens, floor)
        XCTAssertGreaterThanOrEqual(budget.outputTokens, budget.sourceTokens)
    }

    func testBothBackendsReceiveTheSameBudget() throws {
        let plan = try plan(for: sentence(repeated: 14))

        let payload = LocalModelHTTP.chatPayload(system: plan.systemPrompt, prompt: plan.userPrompt, budget: plan.budget)
        let arguments = LocalRefiner.cliArguments(
            plan: plan, model: URL(fileURLWithPath: "/tmp/instruct.gguf"),
            outputURL: URL(fileURLWithPath: "/tmp/out.txt"))
        let predictIndex = try XCTUnwrap(arguments.firstIndex(of: "-n"))
        let contextIndex = try XCTUnwrap(arguments.firstIndex(of: "-c"))

        XCTAssertEqual(payload.max_tokens, plan.budget.outputTokens)
        XCTAssertEqual(arguments[predictIndex + 1], "\(plan.budget.outputTokens)")
        XCTAssertEqual(arguments[contextIndex + 1], "\(contextTokens)")
        XCTAssertFalse(arguments.contains("256"), "the CLI must not carry a hardcoded token ceiling")
    }

    func testOutputBudgetNeverExceedsWhatTheContextHasLeft() throws {
        let plan = try plan(for: sentence(repeated: 14))

        XCTAssertLessThanOrEqual(
            plan.budget.promptTokens + plan.budget.outputTokens + RefinementBudget.safetyMarginTokens,
            contextTokens)
    }

    func testInputThatCannotFitTheContextIsRejectedBeforeAnyBackend() {
        let raw = sentence(repeated: 90)  // ~6500 characters

        XCTAssertThrowsError(try plan(for: raw)) { error in
            guard case VoxlyError.refinementInputTooLong(let estimated, let context) = error else {
                return XCTFail("expected refinementInputTooLong, got \(error)")
            }
            XCTAssertGreaterThan(estimated, context)
            XCTAssertEqual(context, contextTokens)
        }
    }

    func testEstimateIsConservativeForAccentedText() {
        XCTAssertGreaterThan(
            RefinementBudget.estimateTokens("configuração não terminará às três"),
            RefinementBudget.estimateTokens("configuracao nao terminara as tres"))
    }
}
