import Foundation

enum ReminderFrequency: String, Codable, CaseIterable {
    case once = "Once"
    case daily = "Daily"
    case weekly = "Weekly"
    case hourly = "Hourly"
    case custom = "Custom"
    
    var localizedName: String {
        return self.rawValue.localized
    }
}

struct TodoItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var isCompleted: Bool = false
    var reminderDate: Date?
    var hasReminder: Bool = false
    var reminderFrequency: ReminderFrequency = .once
    var reminderInterval: TimeInterval? // Custom interval in seconds
    
    static func == (lhs: TodoItem, rhs: TodoItem) -> Bool {
        return lhs.id == rhs.id &&
               lhs.title == rhs.title &&
               lhs.isCompleted == rhs.isCompleted &&
               lhs.reminderDate == rhs.reminderDate &&
               lhs.hasReminder == rhs.hasReminder &&
               lhs.reminderFrequency == rhs.reminderFrequency &&
               lhs.reminderInterval == rhs.reminderInterval
    }
}

class TodoManager: ObservableObject {
    @Published var todos: [TodoItem] = [] {
        didSet {
            saveTodos()
        }
    }
    
    private let storageKey = "saved_todos"
    
    init() {
        loadTodos()
    }
    
    private func loadTodos() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) {
            self.todos = decoded
        }
    }
    
    private func saveTodos() {
        if let encoded = try? JSONEncoder().encode(todos) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    func addTodo(title: String, reminder: Date? = nil) {
        let newTodo = TodoItem(title: title, reminderDate: reminder, hasReminder: reminder != nil)
        todos.append(newTodo)
    }
    
    func deleteTodo(at offsets: IndexSet) {
        todos.remove(atOffsets: offsets)
    }
    
    func deleteTodo(_ item: TodoItem) {
        if let index = todos.firstIndex(where: { $0.id == item.id }) {
            todos.remove(at: index)
        }
    }
    
    func toggleCompletion(for item: TodoItem) {
        if let index = todos.firstIndex(where: { $0.id == item.id }) {
            todos[index].isCompleted.toggle()
            // Optional: cancel reminder if completed? Let's keep it simple for now.
        }
    }
    
    func updateTodo(_ item: TodoItem) {
        if let index = todos.firstIndex(where: { $0.id == item.id }) {
            todos[index] = item
        }
    }
    

}
