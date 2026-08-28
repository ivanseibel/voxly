import XCTest
@testable import VoxlyApp

final class RefinementOutcomeTests: XCTestCase {
    private let sentinel = LocalRefiner.completionSentinel

    private func serverCompletion(_ text: String, finishReason: String?) -> LocalModelHTTP.ChatCompletion {
        LocalModelHTTP.ChatCompletion(text: text, finishReason: finishReason)
    }

    private func cliTranscript(answer: String) -> String {
        """
        User:
        <source_text>
        i think we should like ship it tomorrow ok
        </source_text>
        Write \(sentinel) on its own line when the rewrite is finished.

        Assistant:
        \(answer)
        """
    }

    func testServerCompletionThatStoppedNormallyIsAccepted() {
        let outcome = LocalRefiner.outcome(forServer: serverCompletion("We should ship it tomorrow.", finishReason: "stop"))

        XCTAssertEqual(outcome, .usable("We should ship it tomorrow."))
    }

    func testServerSentinelIsStrippedFromTheAcceptedText() {
        let outcome = LocalRefiner.outcome(forServer: serverCompletion("We should ship it tomorrow.\n\(sentinel)", finishReason: "stop"))

        XCTAssertEqual(outcome, .usable("We should ship it tomorrow."))
    }

    func testServerCompletionWithoutFinishReasonIsNotTrusted() {
        let outcome = LocalRefiner.outcome(forServer: serverCompletion("We should ship it tomorrow.", finishReason: nil))

        XCTAssertEqual(outcome, .unverified)
    }

    func testUnknownFinishReasonIsNotTrusted() {
        let outcome = LocalRefiner.outcome(forServer: serverCompletion("We should ship it tomorrow.", finishReason: "tool_calls"))

        XCTAssertEqual(outcome, .unverified)
    }

    func testAServerSentinelInsideTheAnswerIsKeptAsContent() {
        let text = "Write \(sentinel) after the rewrite.\nWe should ship it tomorrow."
        let outcome = LocalRefiner.outcome(forServer: serverCompletion(text, finishReason: "stop"))

        XCTAssertEqual(outcome, .usable(text))
    }

    func testLengthFinishReasonIsRejected() {
        let outcome = LocalRefiner.outcome(forServer: serverCompletion("We should ship it tomorrow and also tell the", finishReason: "length"))

        XCTAssertEqual(outcome, .incomplete)
    }

    func testNoPartialServerTextSurvivesAsSuccess() {
        let partial = "We should ship it tomorrow and also tell the"

        guard case .usable(let text) = LocalRefiner.outcome(forServer: serverCompletion(partial, finishReason: "length")) else { return }
        XCTFail("partial text was accepted as a refinement: \(text)")
    }

    func testUnterminatedReasoningIsNotAcceptedAsAnEmptyRefinement() {
        let outcome = LocalRefiner.outcome(forServer: serverCompletion("<think>The user wants me to remove filler", finishReason: "stop"))

        XCTAssertEqual(outcome, .unusable)
    }

    func testUnterminatedReasoningCutOffByTheBudgetIsIncomplete() {
        let outcome = LocalRefiner.outcome(forServer: serverCompletion("<think>The user wants me to remove filler", finishReason: "length"))

        XCTAssertEqual(outcome, .incomplete)
    }

    func testCLIAnswerWithTheCompletionMarkerIsAccepted() {
        let outcome = LocalRefiner.outcome(forCLI: cliTranscript(answer: "We should ship it tomorrow.\n\(sentinel)"))

        XCTAssertEqual(outcome, .usable("We should ship it tomorrow."))
    }

    func testAssistantSeparatorInsideTheAnswerDoesNotDiscardEarlierText() {
        let answer = "First paragraph.\nAssistant:\nSecond paragraph.\n\(sentinel)"
        let outcome = LocalRefiner.outcome(forCLI: cliTranscript(answer: answer))

        XCTAssertEqual(outcome, .usable("First paragraph.\nAssistant:\nSecond paragraph."))
    }

    func testCLIAnswerWithoutTheCompletionMarkerIsNotAccepted() {
        let outcome = LocalRefiner.outcome(forCLI: cliTranscript(answer: "We should ship it tomorrow and also tell the"))

        XCTAssertEqual(outcome, .incomplete)
    }

    func testAMarkerClosingTheLastLineIsCompletionEvidence() {
        // The shape the shipped model actually writes: marker appended after the final sentence.
        let outcome = LocalRefiner.outcome(forCLI: cliTranscript(answer: "We should ship it tomorrow. \(sentinel)"))

        XCTAssertEqual(outcome, .usable("We should ship it tomorrow."))
    }

    func testAnInlineMarkerIsNotCompletionEvidence() {
        let outcome = LocalRefiner.outcome(forCLI: cliTranscript(answer: "We should ship it \(sentinel) tomorrow and also tell the"))

        XCTAssertEqual(outcome, .incomplete)
    }

    func testAMarkerFollowedByMoreTextIsNotCompletionEvidence() {
        let outcome = LocalRefiner.outcome(forCLI: cliTranscript(answer: "We should ship it tomorrow.\n\(sentinel)\nand also tell the"))

        XCTAssertEqual(outcome, .incomplete)
    }

    func testAMarkerEchoedFromTheSourceFollowedByPartialOutputIsRejected() {
        // The model repeats the instruction it was given, then keeps generating until the budget
        // runs out: the marker is present, but nothing ended there.
        let answer = """
            The instruction says to write \(sentinel) on its own line.
            \(sentinel)
            We should ship it tomorrow and also tell the
            """

        XCTAssertEqual(LocalRefiner.outcome(forCLI: cliTranscript(answer: answer)), .incomplete)
    }

    func testATerminalMarkerAfterAnEchoedOneIsAccepted() {
        let answer = """
            We should ship it tomorrow, and the marker \(sentinel) belongs at the end.
            \(sentinel)
            """
        let outcome = LocalRefiner.outcome(forCLI: cliTranscript(answer: answer))

        XCTAssertEqual(outcome, .usable("We should ship it tomorrow, and the marker \(sentinel) belongs at the end."))
    }

    func testTheMarkerEchoedInThePromptDoesNotCountAsCompletion() {
        // The transcript replays the prompt, and the prompt names the marker.
        let transcript = """
            User:
            Write \(sentinel) on its own line when the rewrite is finished.
            We should ship it tomorrow and also tell the
            """

        XCTAssertEqual(LocalRefiner.outcome(forCLI: transcript), .incomplete)
    }

    func testCLIAnswerWithOnlyUnterminatedReasoningIsUnusable() {
        let outcome = LocalRefiner.outcome(forCLI: cliTranscript(answer: "<think>The user wants me to\n\(sentinel)"))

        XCTAssertEqual(outcome, .unusable)
    }

    func testFinishReasonIsDecodedFromTheServerResponse() throws {
        let json = Data("""
            {"choices":[{"message":{"role":"assistant","content":"We should ship it tomorrow and also"},"finish_reason":"length"}]}
            """.utf8)

        let completion = try LocalModelHTTP.completion(from: json)

        XCTAssertTrue(completion.hitTokenLimit)
        XCTAssertEqual(LocalRefiner.outcome(forServer: completion), .incomplete)
    }
}
