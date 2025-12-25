import Foundation
import JavaScriptCore

class DataTransformer {
    static let shared = DataTransformer()
    
    private init() {}
    
    /// Executes a JavaScript transformation on the input data
    /// - Parameters:
    ///   - data: The source data (Array or Dictionary)
    ///   - script: The user's JavaScript code. Must contain a function named 'transform(data)'.
    /// - Returns: The transformed data, or throws an error
    func transform(data: Any, script: String) throws -> Any {
        let context = JSContext()
        
        // 1. Setup Console log support (optional, for debugging)
        let consoleLog: @convention(block) (String) -> Void = { message in
            Logger.log("JS Console: \(message)", level: .info)
        }
        context?.setObject(consoleLog, forKeyedSubscript: "console" as NSString)
        context?.evaluateScript("var console = { log: function(msg) { _consoleLog(msg) } };")
        context?.setObject(consoleLog, forKeyedSubscript: "_consoleLog" as NSString)
        
        // 2. Load the user script
        // We wrap it to ensure 'transform' is available
        context?.evaluateScript(script)
        
        // 3. Get the transform function
        guard let transformFunc = context?.objectForKeyedSubscript("transform") else {
            throw NSError(domain: "DataTransformer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Script must contain a 'function transform(data) { ... }'"])
        }
        
        if transformFunc.isUndefined {
            throw NSError(domain: "DataTransformer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Function 'transform' not found in script."])
        }
        
        // 4. Call the function with data
        guard let result = transformFunc.call(withArguments: [data]) else {
            throw NSError(domain: "DataTransformer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Transformation failed execution."])
        }
        
        if result.isUndefined {
             // It's okay if it returns null/undefined, but we treat it as nil
             throw NSError(domain: "DataTransformer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Transformation returned undefined."])
        }
        
        // 5. Convert back to Swift Object
        return result.toObject() as Any
    }
    
    /// Default template for the script editor
    static let defaultScript = """
    // Write your transformation logic here.
    // The input 'data' is the parsed JSON content.
    // Return the modified data.
    
    function transform(data) {
        // Example: Add a prefix to all keys or values
        // return data.map(item => {
        //     item.imported_at = new Date().toISOString();
        //     return item;
        // });
        
        return data;
    }
    """
}
