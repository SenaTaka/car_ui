//
//  TestSupport.swift
//  car_uiTests
//
//  既知の Swift ランタイム問題の回避: SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor の
//  プロジェクトでは deinit も isolated になり、XCTest 内でローカル生成した
//  クラスの解放時に swift_task_deinitOnExecutor が
//  「pointer being freed was not allocated」で abort する(iOS 26.3 sim で再現)。
//  テスト対象インスタンスをプロセス終了まで保持して解放自体を避ける。
//

import Foundation

enum TestRetention {
    nonisolated(unsafe) private static var objects: [AnyObject] = []

    static func retain<T: AnyObject>(_ object: T) -> T {
        objects.append(object)
        return object
    }
}
