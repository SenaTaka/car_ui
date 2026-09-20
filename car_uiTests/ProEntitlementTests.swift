//
//  ProEntitlementTests.swift
//  car_uiTests
//
//  ProEntitlement.resolve の権利判定(Lifetime / 年額 / 月額 / 広告除去の組み合わせ)。
//

import XCTest
@testable import car_ui

final class ProEntitlementTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testLifetimeOnlyIsPro() {
        let entitlements: [(productID: String, expirationDate: Date?)] = [
            (ProStore.lifetimeProductID, nil)
        ]
        let result = ProEntitlement.resolve(entitlements, now: now)
        XCTAssertTrue(result.isPro)
        XCTAssertFalse(result.isAdFree)
        XCTAssertEqual(result.plan, .lifetime)
    }

    func testYearlyWithinPeriodIsPro() {
        let entitlements: [(productID: String, expirationDate: Date?)] = [
            (ProStore.yearlyProductID, now.addingTimeInterval(3600))
        ]
        let result = ProEntitlement.resolve(entitlements, now: now)
        XCTAssertTrue(result.isPro)
        XCTAssertEqual(result.plan, .yearly)
    }

    func testYearlyExpiredIsNotPro() {
        let entitlements: [(productID: String, expirationDate: Date?)] = [
            (ProStore.yearlyProductID, now.addingTimeInterval(-3600))
        ]
        let result = ProEntitlement.resolve(entitlements, now: now)
        XCTAssertFalse(result.isPro)
        XCTAssertEqual(result.plan, .none)
    }

    func testMonthlyActivePlusAdFreeIsProAndAdFree() {
        let entitlements: [(productID: String, expirationDate: Date?)] = [
            (ProStore.monthlyProductID, now.addingTimeInterval(3600)),
            (ProStore.adFreeProductID, nil)
        ]
        let result = ProEntitlement.resolve(entitlements, now: now)
        XCTAssertTrue(result.isPro)
        XCTAssertTrue(result.isAdFree)
        XCTAssertEqual(result.plan, .monthly)
    }

    func testNoEntitlementsIsNotPro() {
        let result = ProEntitlement.resolve([], now: now)
        XCTAssertFalse(result.isPro)
        XCTAssertFalse(result.isAdFree)
        XCTAssertEqual(result.plan, .none)
    }

    func testNilExpirationDateIsTreatedAsActive() {
        // 非消費型と同じ扱いで nil = 無期限。サブスクで nil が来ることは通常無いが
        // 判定関数としては「失効日が分からなければ有効」の安全側に倒す。
        let entitlements: [(productID: String, expirationDate: Date?)] = [
            (ProStore.yearlyProductID, nil)
        ]
        let result = ProEntitlement.resolve(entitlements, now: now)
        XCTAssertTrue(result.isPro)
        XCTAssertEqual(result.plan, .yearly)
    }
}
