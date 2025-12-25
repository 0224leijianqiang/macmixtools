import Foundation

class GeminiService {
    static let shared = GeminiService()
    
    private init() {}
    
    func generateCommand(prompt: String, context: String = "") async throws -> String {
        let apiKey = SettingsManager.shared.geminiApiKey
        guard !apiKey.isEmpty else {
            throw NSError(domain: "GeminiService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Gemini API Key is not configured in Home settings."])
        }
        
        // Use gemini-2.0-flash as requested (updated from 2.5/3 references)
        let urlString = "https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "GeminiService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL construction."])
        }
        
        var contextStr = ""
        if !context.isEmpty {
            contextStr = "Target System Context: \(context).\n"
        }
        
        let systemPrompt = """
        You are a senior Linux DevOps engineer.
        \(contextStr)
        If the user's request requires multiple steps (e.g. installing software, configuring a service), output a JSON array of steps.
        Format: [{"desc": "Description of step", "cmd": "actual command"}]
        
        If it is a simple single command, just output the command string directly (no JSON).
        
        Do not output markdown code blocks. Output raw text or raw JSON.
        Request: 
        """
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": systemPrompt + prompt]
                    ]
                ]
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        Logger.log("Gemini: Sending request to v1 API...", level: .debug)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
            Logger.log("Gemini: Request failed with status \(httpResponse.statusCode). Body: \(errorBody)", level: .error)
            throw NSError(domain: "GeminiService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error \(httpResponse.statusCode): \(errorBody)"])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let firstCandidate = candidates?.first
        let content = firstCandidate?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        let text = parts?.first?["text"] as? String
        
        var cleanText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Cleanup markdown
        if cleanText.hasPrefix("```json") {
            cleanText = cleanText.replacingOccurrences(of: "```json", with: "")
        } else if cleanText.hasPrefix("```bash") {
            cleanText = cleanText.replacingOccurrences(of: "```bash", with: "")
        } else if cleanText.hasPrefix("```") {
             cleanText = cleanText.replacingOccurrences(of: "```", with: "")
        }
        
        if cleanText.hasSuffix("```") {
             cleanText = String(cleanText.dropLast(3))
        }
        
        return cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func generateTransformationScript(requirement: String, dataType: String) async throws -> String {
        let apiKey = SettingsManager.shared.geminiApiKey
        guard !apiKey.isEmpty else {
            throw NSError(domain: "GeminiService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Gemini API Key is not configured."])
        }
        
        let urlString = "https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "GeminiService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL."])
        }
        
        let systemPrompt = """
        You are a JavaScript expert. Write a JavaScript function named 'transform' to process data for Redis import.
        Input 'data' is either an Array of strings (for List/Set) or an Object/Map (for Hash).
        Requirement: "\(requirement)".
        Data Type Context: \(dataType).
        
        Output ONLY the JavaScript code for the function. No markdown, no explanations.
        Example format:
        function transform(data) {
            // logic
            return modifiedData;
        }
        """
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": systemPrompt]
                    ]
                ]
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "GeminiService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "AI generation failed."])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let parts = candidates?.first?["content"] as? [String: Any]
        let textPart = (parts?["parts"] as? [[String: Any]])?.first
        let text = textPart?["text"] as? String
        
        // Cleanup markdown if AI adds it despite instructions
        var cleanText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if cleanText.hasPrefix("```javascript") {
            cleanText = cleanText.replacingOccurrences(of: "```javascript", with: "")
        }
        if cleanText.hasPrefix("```") {
             cleanText = cleanText.replacingOccurrences(of: "```", with: "")
        }
        if cleanText.hasSuffix("```") {
             cleanText = String(cleanText.dropLast(3))
        }
        
        return cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func generateSQLCommand(prompt: String) async throws -> String {
        let apiKey = SettingsManager.shared.geminiApiKey
        guard !apiKey.isEmpty else {
            throw NSError(domain: "GeminiService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Gemini API Key is not configured."])
        }
        
        let urlString = "https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "GeminiService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL."])
        }
        
        let systemPrompt = """
        You are a MySQL expert. Convert the user's natural language request into a valid MySQL query.
        Output ONLY the SQL query. No markdown formatting (no ```sql), no explanations.
        Request: "\(prompt)"
        """
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": systemPrompt]
                    ]
                ]
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "GeminiService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "AI generation failed."])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let parts = candidates?.first?["content"] as? [String: Any]
        let textPart = (parts?["parts"] as? [[String: Any]])?.first
        let text = textPart?["text"] as? String
        
        var cleanText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Cleanup markdown
        if cleanText.hasPrefix("```sql") {
            cleanText = cleanText.replacingOccurrences(of: "```sql", with: "")
        }
        if cleanText.hasPrefix("```") {
             cleanText = cleanText.replacingOccurrences(of: "```", with: "")
        }
        if cleanText.hasSuffix("```") {
             cleanText = String(cleanText.dropLast(3))
        }
        
        return cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
