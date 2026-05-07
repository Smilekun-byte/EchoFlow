import Foundation

enum Secrets {
    static let deepgramAPIKey: String = {
        guard let key = Bundle.main.infoDictionary?["DEEPGRAM_API_KEY"] as? String,
              !key.isEmpty else {
            fatalError("❌ 找不到 DEEPGRAM_API_KEY，请检查 Config.xcconfig")
        }
        return key
    }()

    static let deepSeekAPIKey: String = {
        Bundle.main.infoDictionary?["DEEPSEEK_API_KEY"] as? String ?? ""
    }()
}
