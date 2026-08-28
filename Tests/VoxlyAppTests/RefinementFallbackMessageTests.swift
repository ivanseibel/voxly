import XCTest
@testable import VoxlyApp

final class RefinementFallbackMessageTests: XCTestCase {
    private func message(for error: Error) -> String {
        DictationCoordinator.insertionMessage(
            result: .inserted, elapsedSeconds: 3.2, transcriptionSeconds: 1.4,
            refinementNote: DictationCoordinator.refinementFallbackNote(for: error))
    }

    func testARefinedDictationReportsOnlyTheInsertionOutcome() {
        let message = DictationCoordinator.insertionMessage(
            result: .inserted, elapsedSeconds: 3.2, transcriptionSeconds: 1.4, refinementNote: nil)

        XCTAssertEqual(message, "Text inserted · processed 3.2s (Whisper 1.4s)")
    }

    func testOverContextFallbackReasonSurvivesInsertion() {
        let message = message(for: VoxlyError.refinementInputTooLong(estimatedTokens: 2400, contextTokens: 2048))

        XCTAssertTrue(message.contains("2400"), message)
        XCTAssertTrue(message.contains("2048"), message)
        XCTAssertTrue(message.contains("raw text kept"), message)
        XCTAssertTrue(message.contains("Text inserted"), message)
    }

    func testTokenBudgetFallbackIsDistinctFromTheOverContextReason() {
        let budgetMessage = message(for: VoxlyError.refinementIncomplete)
        let contextMessage = message(for: VoxlyError.refinementInputTooLong(estimatedTokens: 2400, contextTokens: 2048))

        XCTAssertTrue(budgetMessage.contains("token budget"), budgetMessage)
        XCTAssertNotEqual(budgetMessage, contextMessage)
    }

    func testAnUnavailableModelKeepsTheGenericFallbackReason() {
        let message = message(for: VoxlyError.executableMissing("llama.cpp"))

        XCTAssertTrue(message.hasPrefix("Refinement failed; raw text kept"), message)
    }

    func testTheCapsuleDoesNotReportAnUnrefinedResultAsRefined() {
        let note = DictationCoordinator.refinementFallbackNote(for: VoxlyError.refinementIncomplete)

        XCTAssertEqual(CapsuleState.rawTextKept(reason: note, insertion: .inserted).title, "Raw text inserted")
        XCTAssertNotEqual(CapsuleState.rawTextKept(reason: note, insertion: .inserted), .inserted)
    }

    func testTheCapsuleStillSaysToPasteManuallyWhenTheFallbackOnlyReachedTheClipboard() {
        let note = DictationCoordinator.refinementFallbackNote(for: VoxlyError.refinementIncomplete)
        let copied = CapsuleState.rawTextKept(reason: note, insertion: .copied)

        XCTAssertEqual(copied.title, "Raw text copied — paste manually")
        XCTAssertNotEqual(copied, .rawTextKept(reason: note, insertion: .inserted))
    }

    func testTheCapsuleDetailKeepsTheFallbackReasonForBothDestinations() {
        let note = DictationCoordinator.refinementFallbackNote(for: VoxlyError.refinementInputTooLong(estimatedTokens: 2400, contextTokens: 2048))
        let inserted = CapsuleView(state: .rawTextKept(reason: note, insertion: .inserted), level: 0).detail
        let copied = CapsuleView(state: .rawTextKept(reason: note, insertion: .copied), level: 0).detail

        XCTAssertEqual(inserted, note)
        XCTAssertTrue(copied.contains(note), copied)
        XCTAssertTrue(copied.contains("clipboard"), copied)
    }

    func testTheStatusMessageKeepsBothTheReasonAndTheClipboardDestination() {
        let message = DictationCoordinator.insertionMessage(
            result: .copied, elapsedSeconds: 3.2, transcriptionSeconds: 1.4,
            refinementNote: DictationCoordinator.refinementFallbackNote(for: VoxlyError.refinementIncomplete))

        XCTAssertTrue(message.contains("token budget"), message)
        XCTAssertTrue(message.contains("Text in clipboard"), message)
    }
}
