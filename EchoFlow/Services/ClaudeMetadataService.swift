import Foundation

struct AIMetadata {
    let title: String
    let keywords: [String]
}

final class DeepSeekService {
    static let shared = DeepSeekService()
    private init() {}

    private let endpoint = "https://api.deepseek.com/v1/chat/completions"
    private let model    = "deepseek-chat"

    // MARK: - 生成标题和关键词

    func generateMetadata(original: String, translated: String) async -> AIMetadata? {
        let text = await chat(
            system: "你是标题生成器，只返回JSON，格式：{\"title\":\"5字以内\",\"keywords\":[\"词1\",\"词2\",\"词3\"]}",
            user: "原文：\(original)\n译文：\(translated)"
        )
        guard let text,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = json["title"] as? String, !title.isEmpty
        else { return nil }

        let keywords = json["keywords"] as? [String] ?? []
        return AIMetadata(title: title, keywords: keywords)
    }

    // MARK: - 语音识别纠错

    func correctTranscript(text: String, language: String) async -> String {
        let result = await chat(
            system: "你是语音识别纠错助手。修正明显的识别错误、语法问题。只返回修正后的文本，不加任何解释。",
            user: text
        )
        return result ?? text
    }

    // MARK: - 通用补全（供外部调用）

    func complete(system: String, user: String) async -> String {
        await chat(system: system, user: user) ?? ""
    }

    // MARK: - 备用翻译

    func translateText(text: String, from: String, to: String) async -> String {
        let result = await chat(
            system: "你是专业翻译，只返回翻译结果，不加任何解释。",
            user: "请把以下\(from)翻译成\(to)：\(text)"
        )
        return result ?? text
    }

    // MARK: - 底层请求

    private func chat(system: String, user: String) async -> String? {
        // 优先使用设置页面保存的 key，否则回落到 xcconfig
        let stored = UserDefaults.standard.string(forKey: "deepseekAPIKey") ?? ""
        let apiKey = stored.isEmpty ? Secrets.deepSeekAPIKey : stored
        guard !apiKey.isEmpty else {
            print("ℹ️ DEEPSEEK_API_KEY 未配置")
            return nil
        }
        guard let url = URL(string: endpoint) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 200,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user",   "content": user]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                print("❌ DeepSeek 状态码错误")
                return nil
            }

            guard let json     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices  = json["choices"] as? [[String: Any]],
                  let message  = choices.first?["message"] as? [String: Any],
                  let content  = message["content"] as? String
            else { return nil }

            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("❌ DeepSeek 请求失败: \(error.localizedDescription)")
            return nil
        }
    }
}
