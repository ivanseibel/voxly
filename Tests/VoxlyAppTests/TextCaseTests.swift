import XCTest
@testable import VoxlyApp

/// `TextCase.capitalizingFirstLetter` is applied to the transcription (inside
/// `LocalTranscriber.cleanText`) and again to whatever text is about to be inserted, so a
/// refinement model that lower-cases the first word cannot undo it. It must only ever change
/// the case of one letter.
final class TextCaseTests: XCTestCase {
    func testCapitalizesTheFirstLetter() {
        XCTAssertEqual(TextCase.capitalizingFirstLetter("marcador inicial alpha"), "Marcador inicial alpha")
    }

    func testKeepsEverythingBeforeTheFirstLetter() {
        XCTAssertEqual(TextCase.capitalizingFirstLetter("\"olá, equipe\""), "\"Olá, equipe\"")
        XCTAssertEqual(TextCase.capitalizingFirstLetter("— bom dia"), "— Bom dia")
        XCTAssertEqual(TextCase.capitalizingFirstLetter("2024 foi longo"), "2024 Foi longo")
        XCTAssertEqual(TextCase.capitalizingFirstLetter("(3) itens pendentes"), "(3) Itens pendentes")
    }

    func testChangesNothingElseInTheText() {
        XCTAssertEqual(TextCase.capitalizingFirstLetter("rodar o whisper-server e o llama-cli"),
                       "Rodar o whisper-server e o llama-cli")
    }

    func testIsIdempotent() {
        let once = TextCase.capitalizingFirstLetter("marcador inicial alpha")
        XCTAssertEqual(TextCase.capitalizingFirstLetter(once), once)
    }

    func testLeavesAlreadyCapitalizedTextUnchanged() {
        XCTAssertEqual(TextCase.capitalizingFirstLetter("Voxly está pronto."), "Voxly está pronto.")
    }

    func testHandlesTextWithNoLetter() {
        XCTAssertEqual(TextCase.capitalizingFirstLetter(""), "")
        XCTAssertEqual(TextCase.capitalizingFirstLetter("   "), "   ")
        XCTAssertEqual(TextCase.capitalizingFirstLetter("!?..."), "!?...")
        XCTAssertEqual(TextCase.capitalizingFirstLetter("1 2 3"), "1 2 3")
        XCTAssertEqual(TextCase.capitalizingFirstLetter("🙂"), "🙂")
    }

    /// A caseless script has letters whose `uppercased()` is the letter itself; the guard on
    /// `isLowercase` keeps the function from rewriting a grapheme for no reason.
    func testLeavesCaselessScriptsUnchanged() {
        XCTAssertEqual(TextCase.capitalizingFirstLetter("こんにちは"), "こんにちは")
        XCTAssertEqual(TextCase.capitalizingFirstLetter("مرحبا"), "مرحبا")
    }

    /// "ß".uppercased() is "SS": upper-casing it would add a character to the text, which is
    /// more than a case change, so the letter is left alone.
    func testDoesNotExpandALetterIntoTwoCharacters() {
        XCTAssertEqual(TextCase.capitalizingFirstLetter("ßeta era o nome"), "ßeta era o nome")
    }

    /// A composed grapheme (e + U+0301) must keep its combining mark after the change.
    func testKeepsCombiningMarksOnTheCapitalizedLetter() {
        let decomposed = "e\u{0301}vora tem muralhas"

        let capitalized = TextCase.capitalizingFirstLetter(decomposed)

        XCTAssertEqual(capitalized, "E\u{0301}vora tem muralhas")
        XCTAssertEqual(capitalized.count, decomposed.count)
    }
}
