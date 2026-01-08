import Foundation

enum JSONFormatting {
    enum FormattingError: Error, Equatable {
        case invalidUTF8
        case invalidJSON
        case formatFailed
    }

    static func isCandidate(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    static func validationError(_ text: String) -> FormattingError? {
        guard isCandidate(text) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            return .invalidUTF8
        }
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return nil
        } catch {
            return .invalidJSON
        }
    }

    static func prettyPrinted(_ text: String) -> Result<String, FormattingError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success(text) }
        guard let data = trimmed.data(using: .utf8) else {
            return .failure(.invalidUTF8)
        }

        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            let pretty = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            guard let prettyString = String(data: pretty, encoding: .utf8) else {
                return .failure(.formatFailed)
            }
            return .success(prettyString)
        } catch {
            return .failure(.invalidJSON)
        }
    }
}
