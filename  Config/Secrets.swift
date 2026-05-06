//
//  Secrets.swift
//  EchoFlow
//
//  Created by 漆咚 on 2026/04/24.
//
import Foundation

enum Secrets {
    static let deepgramAPIKey: String = {
        guard let key = Bundle.main.infoDictionary?["DEEPGRAM_API_KEY"] as? String else {
            fatalError("❌ 找不到 DEEPGRAM_API_KEY，请检查 Config.xcconfig")
        }
        return key
    }()
}
