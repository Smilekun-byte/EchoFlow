//
//  AppLanguage.swift
//  共鳴
//
//  Created by 漆咚 on 2026/04/24.
//
import Foundation

enum SupportedLanguage: String, CaseIterable {
    case chinese = "zh"
    case english = "en"
    case japanese = "ja"
    
    var displayName: String {
        switch self {
        case .chinese:  return "中文"
        case .english:  return "English"
        case .japanese: return "日本語"
        }
    }
}
