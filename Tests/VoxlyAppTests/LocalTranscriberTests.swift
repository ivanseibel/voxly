import XCTest
@testable import VoxlyApp

final class LocalTranscriberTests: XCTestCase {
    func testCapitalizesTheFirstLetterOfTranscription() {
        XCTAssertEqual(LocalTranscriber.cleanText("marcador inicial alpha"), "Marcador inicial alpha")
    }

    func testCapitalizesAfterLeadingPunctuationWithoutChangingIt() {
        XCTAssertEqual(LocalTranscriber.cleanText("\"olá, equipe\""), "\"Olá, equipe\"")
    }

    func testKeepsAnAlreadyCapitalizedTranscriptionUnchanged() {
        XCTAssertEqual(LocalTranscriber.cleanText("Voxly está pronto."), "Voxly está pronto.")
    }

    func testCollapsesWhitespaceBeforeCapitalizing() {
        XCTAssertEqual(LocalTranscriber.cleanText("  marcador\n  inicial   alpha "), "Marcador inicial alpha")
    }

    /// Capitalization runs after the blank-audio check, so a marker still becomes empty
    /// instead of being turned into text that no longer matches the marker set.
    func testBlankAudioMarkersStayEmpty() {
        for marker in ["[blank_audio]", "[BLANK_AUDIO]", "[silence]", "(silence)", "[no speech]", "  [blank_audio]  "] {
            XCTAssertEqual(LocalTranscriber.cleanText(marker), "", "marker: \(marker)")
        }
    }

    func testTextWithoutLettersGainsNoContent() {
        XCTAssertEqual(LocalTranscriber.cleanText(""), "")
        XCTAssertEqual(LocalTranscriber.cleanText("   \n\t "), "")
        XCTAssertEqual(LocalTranscriber.cleanText("..."), "...")
        XCTAssertEqual(LocalTranscriber.cleanText("42 42"), "42 42")
    }

    func testEmptyGlossariesProduceNoPrompt() {
        XCTAssertEqual(LocalTranscriber.mergedPrompt(global: "", mode: "   \n "), "")
    }

    func testModeVocabularyIsUsedAlone() {
        XCTAssertEqual(LocalTranscriber.mergedPrompt(global: "", mode: "Kubernetes, PostgreSQL"),
                       "Kubernetes, PostgreSQL")
    }

    func testGlobalPromptComesBeforeModeVocabulary() {
        XCTAssertEqual(LocalTranscriber.mergedPrompt(global: "Voxly", mode: "whisper.cpp, llama.cpp"),
                       "Voxly, whisper.cpp, llama.cpp")
    }

    func testNormalizesSpacingAndEmptyTerms() {
        XCTAssertEqual(LocalTranscriber.mergedPrompt(global: " Voxly ,, ", mode: "  CoreAudio ,\n AVAudioEngine,"),
                       "Voxly, CoreAudio, AVAudioEngine")
    }

    /// Whisper drops anything past ~224 tokens of initial prompt. The cut must land on a
    /// term boundary so the last kept term is never a fragment the model could echo.
    func testTruncatesOnTermBoundary() {
        let term = String(repeating: "a", count: 100)
        let terms = Array(repeating: term, count: 10).joined(separator: ", ")

        let prompt = LocalTranscriber.mergedPrompt(global: "", mode: terms)

        XCTAssertEqual(prompt.split(separator: ",").count, 6)
        XCTAssertLessThanOrEqual(prompt.count, 700)
        XCTAssertFalse(prompt.hasSuffix(","))
    }

    /// Modes persisted before `vocabulary` existed must keep decoding: a throwing decode
    /// makes VoxlyStore fall back to `DictationMode.defaults` and silently wipe the user's
    /// own modes, shortcuts included.
    func testDecodesModesSavedBeforeVocabularyExisted() throws {
        let legacy = """
            [{"id":"11111111-1111-1111-1111-111111111111","name":"Clean text","shortcutKeyCode":61,
              "language":"Portuguese","instructions":"Remove filler words.",
              "modelProfile":"Balanced (local)","automaticInsert":true}]
            """

        let modes = try JSONDecoder().decode([DictationMode].self, from: Data(legacy.utf8))

        XCTAssertEqual(modes.count, 1)
        XCTAssertEqual(modes[0].name, "Clean text")
        XCTAssertEqual(modes[0].shortcutKeyCode, 61)
        XCTAssertEqual(modes[0].vocabulary, "")
    }
}
