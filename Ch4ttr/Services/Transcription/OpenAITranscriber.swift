import Foundation

final class OpenAITranscriber {
    func transcribe(apiKey: String, audioURL: URL, language: AppLanguage) async throws -> String {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw OpenAIError.missingAPIKey }

        let audioData = try Data(contentsOf: audioURL)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func addField(_ name: String, _ value: String) {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendString("\(value)\r\n")
        }

        addField("model", "whisper-1")
        addField("language", language.rawValue)
        addField("response_format", "json")

        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        body.appendString("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        body.appendString("\r\n")
        body.appendString("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIError.httpError(http.statusCode, msg)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let text = decoded.text, !text.isEmpty else { throw OpenAIError.missingTextField }
        return text
    }
}

private struct OpenAIResponse: Decodable {
    let text: String?
}

enum OpenAIError: Error {
    case missingAPIKey
    case invalidResponse
    case httpError(Int, String)
    case missingTextField
}

private extension Data {
    mutating func appendString(_ s: String) {
        append(Data(s.utf8))
    }
}

