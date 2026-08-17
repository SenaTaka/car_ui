//
//  ReviewPromptPolicyTests.swift
//  car_uiTests
//
//  レビュー依頼(requestReview)の発火条件。運転中に絶対出さないことが最優先。
//

import XCTest
@testable import car_ui

final class ReviewPromptPolicyTests: XCTestCase {

    func testSessionEndedIgnoresDemoSessions() {
        let state = ReviewPromptPolicy.State()
        let next = ReviewPromptPolicy.sessionEnded(isDemo: true, liveDuration: 600, state: state)
        XCTAssertEqual(next.qualifyingSessionCount, 0)
        XCTAssertFalse(next.pendingCheck)
    }

    func testSessionEndedIgnoresShortSessions() {
        let state = ReviewPromptPolicy.State()
        let next = ReviewPromptPolicy.sessionEnded(isDemo: false, liveDuration: 90, state: state)
        XCTAssertEqual(next.qualifyingSessionCount, 0)
        XCTAssertFalse(next.pendingCheck)
    }

    func testSessionEndedCountsRealLongSession() {
        let state = ReviewPromptPolicy.State()
        let next = ReviewPromptPolicy.sessionEnded(isDemo: false, liveDuration: 181, state: state)
        XCTAssertEqual(next.qualifyingSessionCount, 1)
        XCTAssertTrue(next.pendingCheck)
    }

    func testShouldRequestReviewNeverFiresInUnsafeContext() {
        var state = ReviewPromptPolicy.State(qualifyingSessionCount: 2, lastRequestedVersion: nil, pendingCheck: true)
        // 接続中・HUD 表示中・走行タブなどはすべて isSafeContext 側で false になる前提。
        let result = ReviewPromptPolicy.shouldRequestReview(state: state, currentVersion: "1.0.2", isSafeContext: false)
        XCTAssertFalse(result.shouldRequest)
        // 安全になるまで pendingCheck は温存される(次のフォアグラウンド復帰等で再判定)。
        XCTAssertTrue(result.nextState.pendingCheck)
        state = result.nextState
        XCTAssertEqual(state, ReviewPromptPolicy.State(qualifyingSessionCount: 2, lastRequestedVersion: nil, pendingCheck: true))
    }

    func testShouldRequestReviewFiresOnSecondQualifyingSessionInSafeContext() {
        let state = ReviewPromptPolicy.State(qualifyingSessionCount: 2, lastRequestedVersion: nil, pendingCheck: true)
        let result = ReviewPromptPolicy.shouldRequestReview(state: state, currentVersion: "1.0.2", isSafeContext: true)
        XCTAssertTrue(result.shouldRequest)
        XCTAssertEqual(result.nextState.lastRequestedVersion, "1.0.2")
        XCTAssertFalse(result.nextState.pendingCheck)
    }

    func testShouldRequestReviewSkipsWhenAlreadyRequestedForVersion() {
        let state = ReviewPromptPolicy.State(qualifyingSessionCount: 3, lastRequestedVersion: "1.0.2", pendingCheck: true)
        let result = ReviewPromptPolicy.shouldRequestReview(state: state, currentVersion: "1.0.2", isSafeContext: true)
        XCTAssertFalse(result.shouldRequest)
        XCTAssertFalse(result.nextState.pendingCheck)
    }

    func testShouldRequestReviewSkipsBelowThresholdButClearsPendingCheck() {
        let state = ReviewPromptPolicy.State(qualifyingSessionCount: 1, lastRequestedVersion: nil, pendingCheck: true)
        let result = ReviewPromptPolicy.shouldRequestReview(state: state, currentVersion: "1.0.2", isSafeContext: true)
        XCTAssertFalse(result.shouldRequest)
        XCTAssertFalse(result.nextState.pendingCheck)
        XCTAssertNil(result.nextState.lastRequestedVersion)
    }
}
