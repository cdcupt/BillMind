import Foundation
import UIKit

enum AIError: LocalizedError {
    case noAPIKey
    case invalidImage
    case invalidResponse(String)
    case httpError(Int, String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key configured"
        case .invalidImage: return "Could not process image"
        case .invalidResponse(let msg): return "Invalid response: \(msg)"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .networkError(let err): return err.localizedDescription
        }
    }
}

final class AIService {

    /// Recognize a bill from one or more images using the configured AI provider
    func recognizeBill(
        images: [UIImage],
        provider: AIProvider,
        model: String,
        apiKey: String
    ) async throws -> AIRecognitionResult {
        guard !apiKey.isEmpty else { throw AIError.noAPIKey }

        // Convert images to JPEG base64
        let imageDataList = try images.map { image -> Data in
            guard let data = image.jpegData(compressionQuality: 0.8) else {
                throw AIError.invalidImage
            }
            return data
        }

        // Build request based on provider
        let (request, isGemini) = try buildRequest(
            imageDataList: imageDataList,
            provider: provider,
            model: model,
            apiKey: apiKey
        )

        // Execute
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 0

        guard (200...299).contains(statusCode) else {
            let errorMsg = parseErrorMessage(data: data, isGemini: isGemini)
            throw AIError.httpError(statusCode, errorMsg)
        }

        // Parse response
        let text = try extractText(data: data, isGemini: isGemini)
        return try parseRecognitionResult(text)
    }

    // MARK: - Request Building

    private func buildRequest(
        imageDataList: [Data],
        provider: AIProvider,
        model: String,
        apiKey: String
    ) throws -> (URLRequest, Bool) {
        if provider.usesGeminiFormat {
            return (try buildGeminiRequest(imageDataList: imageDataList, model: model, apiKey: apiKey), true)
        } else {
            return (try buildOpenAIRequest(imageDataList: imageDataList, provider: provider, model: model, apiKey: apiKey), false)
        }
    }

    private func buildGeminiRequest(imageDataList: [Data], model: String, apiKey: String) throws -> URLRequest {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-goog-api-key")
        request.timeoutInterval = 60

        // Build parts: images + text prompt
        var parts: [[String: Any]] = imageDataList.map { data in
            ["inlineData": ["mimeType": "image/jpeg", "data": data.base64EncodedString()]]
        }
        parts.append(["text": Prompts.billRecognition])

        let body: [String: Any] = [
            "contents": [["parts": parts]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func buildOpenAIRequest(imageDataList: [Data], provider: AIProvider, model: String, apiKey: String) throws -> URLRequest {
        let url = URL(string: provider.baseURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        // Build content array: images + text
        var content: [[String: Any]] = imageDataList.map { data in
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())"]]
        }
        content.append(["type": "text", "text": Prompts.billRecognition])

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": content]],
            "max_tokens": 2048
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Response Parsing

    private func extractText(data: Data, isGemini: Bool) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.invalidResponse("Cannot parse JSON")
        }

        if isGemini {
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                throw AIError.invalidResponse("Missing candidates")
            }
            for part in parts {
                if let text = part["text"] as? String { return text }
            }
            throw AIError.invalidResponse("No text in response")
        } else {
            guard let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw AIError.invalidResponse("Missing choices")
            }
            return content
        }
    }

    private func parseRecognitionResult(_ text: String) throws -> AIRecognitionResult {
        // Clean up: remove markdown code blocks if present
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
        if cleaned.hasPrefix("```") { cleaned = String(cleaned.dropFirst(3)) }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw AIError.invalidResponse("Cannot encode text")
        }

        do {
            return try JSONDecoder().decode(AIRecognitionResult.self, from: data)
        } catch {
            throw AIError.invalidResponse("JSON decode failed: \(error.localizedDescription)")
        }
    }

    private func parseErrorMessage(data: Data, isGemini: Bool) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? "Unknown error"
        }
        if let error = json["error"] as? [String: Any], let msg = error["message"] as? String {
            return msg
        }
        return "Unknown error"
    }
}
