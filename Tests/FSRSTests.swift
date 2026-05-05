import XCTest
@testable import Flashcards

final class FSRSTests: XCTestCase {

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func freshCard() -> Card {
        let c = Card()
        c.front = "Test Q"
        c.back  = "Test A"
        return c
    }

    // ── FSRS algorithm ────────────────────────────────────────────────────────

    func test_firstReview_easy_setsStabilityAndDifficulty() {
        let card = freshCard()
        XCTAssertNil(card.fsrsStability)
        FSRS.apply(rating: 5, to: card)
        XCTAssertNotNil(card.fsrsStability)
        XCTAssertNotNil(card.fsrsDifficulty)
        XCTAssertEqual(card.repetitions, 1)
        XCTAssertGreaterThan(card.fsrsStability!, 0)
        XCTAssertGreaterThanOrEqual(card.fsrsDifficulty!, 1)
        XCTAssertLessThanOrEqual(card.fsrsDifficulty!, 10)
    }

    func test_firstReview_again_hasLowStability() {
        let easy  = freshCard(); FSRS.apply(rating: 5, to: easy)
        let again = freshCard(); FSRS.apply(rating: 1, to: again)
        XCTAssertLessThan(again.fsrsStability!, easy.fsrsStability!)
    }

    func test_secondReview_increases_interval() {
        let card = freshCard()
        FSRS.apply(rating: 4, to: card)
        let interval1 = card.interval
        FSRS.apply(rating: 4, to: card)
        XCTAssertGreaterThan(card.interval, interval1)
    }

    func test_hardRating_increases_difficulty() {
        let card = freshCard()
        FSRS.apply(rating: 5, to: card)          // easy first review
        let d1 = card.fsrsDifficulty!
        FSRS.apply(rating: 2, to: card)          // hard second review
        XCTAssertGreaterThan(card.fsrsDifficulty!, d1)
    }

    func test_easyRating_decreases_difficulty() {
        let card = freshCard()
        FSRS.apply(rating: 1, to: card)          // again first review
        let d1 = card.fsrsDifficulty!
        FSRS.apply(rating: 5, to: card)          // easy second review
        XCTAssertLessThan(card.fsrsDifficulty!, d1)
    }

    func test_difficulty_clamped_1_to_10() {
        let card = freshCard()
        for _ in 0..<10 { FSRS.apply(rating: 1, to: card) }
        XCTAssertGreaterThanOrEqual(card.fsrsDifficulty!, 1)
        XCTAssertLessThanOrEqual(card.fsrsDifficulty!, 10)
    }

    func test_maximumInterval_not_exceeded() {
        let card = freshCard()
        for _ in 0..<50 { FSRS.apply(rating: 5, to: card) }
        XCTAssertLessThanOrEqual(card.interval, FSRS.maximumInterval)
    }

    func test_retrievability_decays_over_time() {
        let card = freshCard()
        FSRS.apply(rating: 4, to: card)
        card.lastReviewed = Date(timeIntervalSinceNow: -5 * 86400)  // pretend reviewed 5 days ago

        let r5  = FSRS.retrievability(for: card)
        card.lastReviewed = Date(timeIntervalSinceNow: -30 * 86400) // 30 days ago
        let r30 = FSRS.retrievability(for: card)

        XCTAssertGreaterThan(r5,  r30)
        XCTAssertGreaterThan(r5,  0)
        XCTAssertLessThanOrEqual(r5, 1)
    }

    func test_retrievability_returns_zero_for_new_card() {
        let card = freshCard()
        XCTAssertEqual(FSRS.retrievability(for: card), 0)
    }

    func test_weights_count_is_17() {
        XCTAssertEqual(FSRS.w.count, 17)
    }
}

// ── PracticeQueue tests ───────────────────────────────────────────────────────

final class PracticeQueueTests: XCTestCase {

    private func card(id: UUID = UUID(), isNew: Bool = false, due daysOffset: Int = -1, struggling: Bool = false, difficulty: Int = 0) -> Card {
        let c = Card(); c.id = id
        c.front = "Q\(daysOffset)"; c.back = "A"
        if !isNew {
            c.repetitions = 1
            c.fsrsStability   = 4.0
            c.fsrsDifficulty  = 5.0
            c.lastReviewed = Date(timeIntervalSinceNow: -5 * 86400)
            c.nextReview   = Date(timeIntervalSinceNow: Double(daysOffset) * 86400)
        }
        if struggling {
            c.wrongCount   = 3
            c.correctCount = 1
        }
        c.userDifficulty = difficulty
        return c
    }

    func test_due_cards_come_before_new_cards() {
        let due = card(isNew: false, due: -1)
        let new = card(isNew: true)
        let queue = PracticeQueue.ordered([new, due])
        XCTAssertFalse(queue.first?.isNew ?? true, "Due card should be first")
    }

    func test_struggling_cards_come_first_among_due() {
        let normal    = card(isNew: false, due: -1, struggling: false)
        let struggling = card(isNew: false, due: -1, struggling: true)
        let queue = PracticeQueue.ordered([normal, struggling])
        XCTAssertTrue(queue.first?.isStruggling ?? false)
    }

    func test_new_card_limit_respected() {
        let cards = (0..<30).map { _ in card(isNew: true) }
        let queue = PracticeQueue.ordered(cards, dailyNewCardLimit: 10)
        let newCount = queue.filter { $0.isNew }.count
        XCTAssertLessThanOrEqual(newCount, 10)
    }

    func test_round_size_respected() {
        let cards = (0..<50).map { _ in card(isNew: false, due: -1) }
        let queue = PracticeQueue.ordered(cards, roundSize: 20)
        XCTAssertEqual(queue.count, 20)
    }

    func test_neverForget_hard_cards_appear_first() {
        let hard    = card(isNew: false, due: -2, difficulty: 3)
        let normal  = card(isNew: false, due: -1, difficulty: 0)
        // Both due; hard should be first with neverForgetEnabled
        let queue = PracticeQueue.ordered([normal, hard], neverForgetEnabled: true)
        XCTAssertEqual(queue.first?.userDifficulty, 3)
    }

    func test_filter_dueOnly_excludes_future_cards() {
        let due    = card(isNew: false, due: -1)
        let future = card(isNew: false, due: +5)
        let queue = PracticeQueue.ordered([due, future], filter: .dueOnly)
        XCTAssertFalse(queue.contains { $0.id == future.id })
    }

    func test_filter_struggling_returns_only_struggling() {
        let ok   = card(isNew: false, due: -1, struggling: false)
        let bad  = card(isNew: false, due: -1, struggling: true)
        let queue = PracticeQueue.ordered([ok, bad], filter: .struggling)
        XCTAssertTrue(queue.allSatisfy { $0.isStruggling })
    }

    func test_distractors_returns_n_items() {
        let pool = (0..<20).map { "Answer \($0)" }
        let d = PracticeQueue.distractors(for: "Answer 0", from: pool, n: 3)
        XCTAssertEqual(d.count, 3)
    }

    func test_distractors_does_not_include_correct() {
        let pool = (0..<20).map { "Answer \($0)" }
        let d = PracticeQueue.distractors(for: "Answer 5", from: pool, n: 3)
        XCTAssertFalse(d.contains("Answer 5"))
    }

    func test_distractors_all_distinct() {
        let pool = (0..<20).map { "Answer \($0)" }
        let d = PracticeQueue.distractors(for: "Answer 0", from: pool, n: 5)
        XCTAssertEqual(d.count, Set(d).count)
    }
}
