import Vapor
import Fluent
import Foundation

/// `POST /v1/minds` — generate a "Mind": a sketch-style infographic of a trip's
/// expense timeline. Server-side image generation via Gemini, using the app's own
/// key — the client never needs an API key. The trip is tenant-scoped to the
/// caller; deleted bills are excluded by Fluent's soft-delete query.
struct MindController: RouteCollection {
    let generator: MindGenerating

    init(generator: MindGenerating) { self.generator = generator }

    func boot(routes: RoutesBuilder) throws {
        let group = routes.grouped("v1").grouped(UserAuthMiddleware())
        group.post("minds", use: generate)
    }

    func generate(_ req: Request) async throws -> MindResponse {
        let user = try req.auth.require(User.self)
        let uid = try user.requireID()
        let body = try req.content.decode(MindRequest.self)

        guard let trip = try await Trip.query(on: req.db)
            .filter(\.$id == body.tripID).filter(\.$owner.$id == uid).first()
        else { throw Abort(.notFound, reason: "trip not found") }

        let tripID = try trip.requireID()
        let bills = try await Bill.query(on: req.db)
            .filter(\.$trip.$id == tripID)
            .sort(\.$date, .ascending)
            .all()
        guard !bills.isEmpty else {
            throw Abort(.unprocessableEntity, reason: "Add some bills to this trip first.")
        }

        let prompt = Self.buildPrompt(trip: trip, bills: bills)
        let image = try await generator.generate(prompt: prompt, on: req)
        return MindResponse(imageBase64: image.base64, mimeType: image.mime)
    }

    /// Build the timeline narrative the image model visualizes. The image only
    /// needs the *shape* of the data (the prompt asks for decorative, non-literal
    /// text), so a plain Decimal description is enough.
    static func buildPrompt(trip: Trip, bills: [Bill]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var lines = "Journal: \(trip.name)\nCurrency: \(trip.currencyCode)\n\nBill Timeline:\n"
        var total = Decimal.zero
        for bill in bills {
            total += bill.amount
            let date = formatter.string(from: bill.date)
            let category = bill.categoryRaw ?? "misc"
            let merchant = bill.merchant ?? category
            lines += "- \(date): \(merchant) — \(trip.currencyCode) \(bill.amount) (\(category))\n"
        }
        lines += "\nTotal: \(trip.currencyCode) \(total)"

        return """
        Create a beautiful, artistic sketch-style infographic image for a travel expense journal.

        The image should be:
        - Hand-drawn/sketch style with warm colors (cream, teal, dusty rose, sage green)
        - A vertical timeline layout showing expenses chronologically
        - Each expense shown as a cute illustrated card on the timeline
        - Small cute icons per category (food=bowl, transport=car, accommodation=bed, shopping=bag, etc.)
        - The journal title "\(trip.name)" at the top in a decorative hand-lettered style
        - Total amount at the bottom in a highlighted circle
        - Decorative elements: small stars, dots, doodle borders
        - Warm, cozy, journal/planner aesthetic
        - NO real text that needs to be readable — use decorative/abstract text shapes
        - The overall feel should be like a page from a beautiful travel journal

        Here is the expense data to visualize:
        \(lines)
        """
    }
}

// MARK: - DTOs

struct MindRequest: Content { let tripID: UUID }
struct MindResponse: Content {
    let imageBase64: String
    let mimeType: String
}

// MARK: - Generator

/// Produces an image (base64 + mime) from a prompt. Injectable so the controller
/// is tested without calling Gemini.
protocol MindGenerating: Sendable {
    func generate(prompt: String, on req: Request) async throws -> (base64: String, mime: String)
}

/// Live: Gemini image generation. Returns the first inline image part. The
/// response parse is pure/static and unit-tested without a network call.
struct GeminiMindGenerator: MindGenerating {
    let model: String

    init(model: String = "gemini-3.1-flash-image") { self.model = model }

    func generate(prompt: String, on req: Request) async throws -> (base64: String, mime: String) {
        guard let key = Environment.get("GEMINI_API_KEY"), !key.isEmpty else {
            throw Abort(.serviceUnavailable, reason: "GEMINI_API_KEY not configured")
        }
        let uri = URI(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)")
        let body = GImgReq(
            contents: [GImgContent(role: "user", parts: [GImgPart(text: prompt)])],
            generationConfig: GImgGenConfig(responseModalities: ["TEXT", "IMAGE"])
        )
        let response = try await req.client.post(uri) { try $0.content.encode(body) }
        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "Gemini image gen returned \(response.status.code)")
        }
        let data = response.body.map { Data(buffer: $0) } ?? Data()
        return try Self.parse(data)
    }

    /// Pull the first inline image from a generateContent response.
    static func parse(_ data: Data) throws -> (base64: String, mime: String) {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let parts = (((obj?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        for part in parts {
            if let inline = part["inlineData"] as? [String: Any],
               let base64 = inline["data"] as? String, !base64.isEmpty {
                let mime = (inline["mimeType"] as? String) ?? "image/png"
                return (base64, mime)
            }
        }
        throw Abort(.badGateway, reason: "image generation returned no image")
    }
}

// Gemini image request (encode-only).
struct GImgReq: Content {
    let contents: [GImgContent]
    let generationConfig: GImgGenConfig
}
struct GImgContent: Content { let role: String; let parts: [GImgPart] }
struct GImgPart: Content { let text: String }
struct GImgGenConfig: Content { let responseModalities: [String] }
