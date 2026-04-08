import Foundation

final class CleanupService {
    func clean(_ text: String) async -> String {
        switch Config.cleanupMode {
        case .fast:
            return cleanFast(text)
        case .llm:
            if let llmResult = await cleanWithLLM(text) {
                return llmResult
            }
            print("[Transcriberino] LLM cleanup failed, falling back to fast mode.")
            return cleanFast(text)
        }
    }

    // MARK: - Mode A: Fast (Rule-based)

    private func cleanFast(_ text: String) -> String {
        var result = text

        // 1. Trim whitespace
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. Remove clear filler words (always filler, no context needed)
        let alwaysFillerPattern = #"(?i)\b(um|uh|er|ah|you know|I mean)\b[,]?\s*"#
        if let regex = try? NSRegularExpression(pattern: alwaysFillerPattern) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }

        // 3. Remove "like" only when clearly filler (followed by comma, or start of sentence)
        let likeFillerPattern = #"(?i)(?:^|\.\s+)like[,\s]+"#  // "Like, ..." or sentence-start "like"
        if let regex = try? NSRegularExpression(pattern: likeFillerPattern) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }

        // 4. Remove standalone "basically", "actually", "literally", "right" when followed by comma
        let contextFillerPattern = #"(?i)\b(basically|actually|literally|right)[,]\s*"#
        if let regex = try? NSRegularExpression(pattern: contextFillerPattern) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }

        // 5. Collapse repeated words
        let repeatedPattern = #"\b(\w+)\s+\1\b"#
        if let regex = try? NSRegularExpression(pattern: repeatedPattern, options: .caseInsensitive) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1"
            )
        }

        // 6. Normalize whitespace
        let whitespacePattern = #"\s{2,}"#
        if let regex = try? NSRegularExpression(pattern: whitespacePattern) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: " "
            )
        }

        // 7. Strip leading "So,", "Okay,", "Well,"
        let leadingPattern = #"^(So|Okay|Well|OK),?\s*"#
        if let regex = try? NSRegularExpression(pattern: leadingPattern, options: .caseInsensitive) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }

        // 8. Capitalize sentence starts
        result = capitalizeSentences(result)

        // 9. Ensure ending punctuation
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if !result.isEmpty {
            let lastChar = result.last!
            if !".!?".contains(lastChar) {
                result += "."
            }
        }

        return result
    }

    private func capitalizeSentences(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = ""
        var capitalizeNext = true

        for char in text {
            if capitalizeNext && char.isLetter {
                result.append(char.uppercased())
                capitalizeNext = false
            } else {
                result.append(char)
            }
            if ".!?".contains(char) {
                capitalizeNext = true
            }
        }

        return result
    }

    // MARK: - Mode B: LLM (Ollama)

    private func cleanWithLLM(_ text: String) async -> String? {
        let prompt = """
        Clean up the following dictated text. Fix grammar, remove filler words, \
        and make it read naturally. Do NOT change the meaning or add new content. \
        Return ONLY the cleaned text, nothing else.

        Text: \(text)
        """

        let body: [String: Any] = [
            "model": Config.ollamaModel,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": 0.0,
            ],
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: Config.ollamaURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = Config.ollamaTimeoutSeconds

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseText = json["response"] as? String else { return nil }

            return stripPreamble(responseText.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            print("[Transcriberino] Ollama request failed: \(error)")
            return nil
        }
    }

    private func stripPreamble(_ text: String) -> String {
        let preamblePatterns = [
            #"^(Here('s| is) the cleaned( up)? text:?\s*)"#,
            #"^(Cleaned text:?\s*)"#,
            #"^(Sure[,!.]?\s*(Here('s| is)[^:]*:)?\s*)"#,
        ]

        var result = text
        for pattern in preamblePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // Strip surrounding quotes if present
        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count > 2 {
            result = String(result.dropFirst().dropLast())
        }

        return result
    }
}
