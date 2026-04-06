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
        apiKey: String,
        demoMode: Bool = false
    ) async throws -> AIRecognitionResult {
        if demoMode { return DemoData.randomRecognitionResult() }
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

// MARK: - Demo Data

enum DemoData {

    private static let demoResults: [AIRecognitionResult] = [
        AIRecognitionResult(
            merchant: "Starbucks Coffee",
            date: "2026-04-05",
            totalAmount: 8.50,
            currency: "USD",
            category: "food",
            lineItems: [
                .init(description: "Caramel Latte", quantity: 1, unitPrice: 5.50, amount: 5.50),
                .init(description: "Butter Croissant", quantity: 1, unitPrice: 3.00, amount: 3.00),
            ],
            notes: "Morning coffee"
        ),
        AIRecognitionResult(
            merchant: "Tokyo Metro",
            date: "2026-04-04",
            totalAmount: 280,
            currency: "JPY",
            category: "transport",
            lineItems: [
                .init(description: "Day Pass", quantity: 1, unitPrice: 280, amount: 280),
            ],
            notes: "Subway day pass"
        ),
        AIRecognitionResult(
            merchant: "Hotel Marais",
            date: "2026-04-03",
            totalAmount: 165.00,
            currency: "EUR",
            category: "accommodation",
            lineItems: [
                .init(description: "Standard Room - 1 Night", quantity: 1, unitPrice: 145.00, amount: 145.00),
                .init(description: "City Tax", quantity: 1, unitPrice: 5.00, amount: 5.00),
                .init(description: "Breakfast Buffet", quantity: 1, unitPrice: 15.00, amount: 15.00),
            ],
            notes: "1 night stay with breakfast"
        ),
        AIRecognitionResult(
            merchant: "Uniqlo Ginza",
            date: "2026-04-04",
            totalAmount: 4980,
            currency: "JPY",
            category: "shopping",
            lineItems: [
                .init(description: "AIRism T-Shirt", quantity: 2, unitPrice: 1490, amount: 2980),
                .init(description: "Socks Pack", quantity: 1, unitPrice: 990, amount: 990),
                .init(description: "Compact Umbrella", quantity: 1, unitPrice: 1010, amount: 1010),
            ],
            notes: nil
        ),
        AIRecognitionResult(
            merchant: "Haidilao Hot Pot",
            date: "2026-04-06",
            totalAmount: 326.00,
            currency: "CNY",
            category: "food",
            lineItems: [
                .init(description: "Mandarin Duck Pot Base", quantity: 1, unitPrice: 78.00, amount: 78.00),
                .init(description: "Sliced Beef", quantity: 2, unitPrice: 58.00, amount: 116.00),
                .init(description: "Shrimp Paste", quantity: 1, unitPrice: 38.00, amount: 38.00),
                .init(description: "Vegetables Combo", quantity: 1, unitPrice: 46.00, amount: 46.00),
                .init(description: "Drinks", quantity: 2, unitPrice: 24.00, amount: 48.00),
            ],
            notes: "Dinner for 2"
        ),
    ]

    static func randomRecognitionResult() -> AIRecognitionResult {
        demoResults.randomElement()!
    }

    /// Generate a placeholder Mind infographic from journal data
    static func generatePlaceholderMind(journal: Journal) -> UIImage {
        let size = CGSize(width: 800, height: 1200)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Background
            UIColor(red: 253/255, green: 246/255, blue: 236/255, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 32, weight: .bold),
                .foregroundColor: UIColor(red: 139/255, green: 90/255, blue: 43/255, alpha: 1)
            ]
            let title = journal.name
            title.draw(at: CGPoint(x: 40, y: 40), withAttributes: titleAttrs)

            // Subtitle
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .regular),
                .foregroundColor: UIColor(red: 160/255, green: 140/255, blue: 110/255, alpha: 1)
            ]
            "Travel Expense Timeline".draw(at: CGPoint(x: 40, y: 82), withAttributes: subAttrs)

            // Timeline line
            let lineX: CGFloat = 60
            UIColor(red: 217/255, green: 119/255, blue: 6/255, alpha: 0.3).setStroke()
            let linePath = UIBezierPath()
            linePath.move(to: CGPoint(x: lineX, y: 130))
            linePath.addLine(to: CGPoint(x: lineX, y: size.height - 150))
            linePath.lineWidth = 3
            linePath.setLineDash([6, 4], count: 2, phase: 0)
            linePath.stroke()

            // Bills
            let billsSorted = journal.bills.sorted { $0.date < $1.date }
            let cardColors: [UIColor] = [
                UIColor(red: 217/255, green: 119/255, blue: 6/255, alpha: 0.12),
                UIColor(red: 13/255, green: 148/255, blue: 136/255, alpha: 0.12),
                UIColor(red: 190/255, green: 120/255, blue: 140/255, alpha: 0.12),
                UIColor(red: 130/255, green: 160/255, blue: 120/255, alpha: 0.12),
            ]
            let currencySymbol = CurrencyInfo.popular.first(where: { $0.code == journal.currency })?.symbol ?? journal.currency

            let maxBills = min(billsSorted.count, 8)
            let spacing = min(120, (size.height - 300) / CGFloat(max(maxBills, 1)))

            for (i, bill) in billsSorted.prefix(maxBills).enumerated() {
                let y = 140 + CGFloat(i) * spacing

                // Dot on timeline
                UIColor(red: 217/255, green: 119/255, blue: 6/255, alpha: 1).setFill()
                let dot = UIBezierPath(ovalIn: CGRect(x: lineX - 6, y: y + 8, width: 12, height: 12))
                dot.fill()

                // Card
                let cardRect = CGRect(x: 90, y: y, width: size.width - 130, height: spacing - 12)
                let cardColor = cardColors[i % cardColors.count]
                cardColor.setFill()
                let card = UIBezierPath(roundedRect: cardRect, cornerRadius: 12)
                card.fill()

                UIColor(red: 200/255, green: 180/255, blue: 150/255, alpha: 0.5).setStroke()
                card.lineWidth = 1
                card.stroke()

                // Bill text
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MMM d"
                let dateStr = dateFormatter.string(from: bill.date)
                let merchant = bill.merchant ?? bill.category.englishName

                let nameAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                    .foregroundColor: UIColor(red: 60/255, green: 50/255, blue: 40/255, alpha: 1)
                ]
                let detailAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: UIColor(red: 120/255, green: 100/255, blue: 80/255, alpha: 1)
                ]
                let amountAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                    .foregroundColor: UIColor(red: 217/255, green: 119/255, blue: 6/255, alpha: 1)
                ]

                merchant.draw(at: CGPoint(x: cardRect.minX + 14, y: cardRect.minY + 10), withAttributes: nameAttrs)
                "\(dateStr)  •  \(bill.category.englishName)".draw(at: CGPoint(x: cardRect.minX + 14, y: cardRect.minY + 34), withAttributes: detailAttrs)

                let amountStr = "\(currencySymbol)\(bill.amount.formatted2)"
                let amountSize = amountStr.size(withAttributes: amountAttrs)
                amountStr.draw(at: CGPoint(x: cardRect.maxX - amountSize.width - 14, y: cardRect.minY + 14), withAttributes: amountAttrs)
            }

            // Total at bottom
            let totalY = size.height - 100
            UIColor(red: 217/255, green: 119/255, blue: 6/255, alpha: 0.15).setFill()
            let totalRect = UIBezierPath(roundedRect: CGRect(x: 200, y: totalY, width: 400, height: 50), cornerRadius: 25)
            totalRect.fill()

            let totalAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor(red: 217/255, green: 119/255, blue: 6/255, alpha: 1)
            ]
            let totalStr = "Total: \(currencySymbol)\(journal.totalAmount.formattedCurrency)"
            let totalSize = totalStr.size(withAttributes: totalAttrs)
            totalStr.draw(at: CGPoint(x: 400 - totalSize.width / 2, y: totalY + 12), withAttributes: totalAttrs)

            // Demo badge
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor(red: 160/255, green: 140/255, blue: 110/255, alpha: 0.6)
            ]
            "Demo Mode Preview".draw(at: CGPoint(x: size.width - 160, y: size.height - 30), withAttributes: badgeAttrs)
        }
    }
}
