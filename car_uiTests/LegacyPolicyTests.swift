//
//  LegacyPolicyTests.swift
//  car_uiTests
//
//  LegacyPolicy.decide: 更新前からの無料ユーザー(grandfather)は一度だけ判定し、以後は再評価しない。
//

import XCTest
@testable import car_ui

final class LegacyPolicyTests: XCTestCase {

    func testExistingUserWithCompletedOnboardingIsGrandfathered() {
        // 更新前ビルドから使っていた = onboarding.completed が既に true
        let result = LegacyPolicy.decide(onboardingCompleted: true, alreadyDecided: false, previous: false)
        XCTAssertTrue(result)
    }

    func testFreshInstallIsNotGrandfathered() {
        // 新規インストールは onboarding.completed が未完了のまま評価される
        let result = LegacyPolicy.decide(onboardingCompleted: false, alreadyDecided: false, previous: false)
        XCTAssertFalse(result)
    }

    func testAlreadyDecidedReturnsPreviousRegardlessOfOnboarding() {
        // 一度判定済みなら、以後 onboarding の状態が変わっても previous を維持する
        XCTAssertTrue(LegacyPolicy.decide(onboardingCompleted: false, alreadyDecided: true, previous: true))
        XCTAssertFalse(LegacyPolicy.decide(onboardingCompleted: true, alreadyDecided: true, previous: false))
    }
}
