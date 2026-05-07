import Foundation

struct ClaudeMetadata {
    let title: String
    let keywords: [String]
}

final class ClaudeMetadataService {
    static let shared = ClaudeMetadataService()
    private init() {}

    func generateMetadata(original: String, translated: String) async -> ClaudeMetadata? {
        let apiKey = Secrets.anthropicAPIKey
        guard !apiKey.isEmpty else {
            print("ℹ️ ANTHROPIC_API_KEY 未配置，跳过标题生成")
            return nil
        }

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 200,
            "system": "你是一个对话标题生成器。只返回 JSON，格式：{\"title\":\"5字以内标题\",\"keywords\":[\"词1\",\"词2\",\"词3\"]}",
            "messages": [
                ["role": "user", "content": "原文：\(original)\n译文：\(translated)"]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let text = content.first?["text"] as? String,
                  let textData = text.data(using: .utf8),
                  let meta = try? JSONSerialization.jsonObject(with: textData) as? [String: Any],
                  let title = meta["title"] as? String, !title.isEmpty
            else { return nil }

            let keywords = meta["keywords"] as? [String] ?? []
            return ClaudeMetadata(title: title, keywords: keywords)
        } catch {
            print("❌ Claude 元数据生成失败: \(error.localizedDescription)")
            return nil
        }
    }
}
