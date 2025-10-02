import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp: Date
    let citations: [Citation]
    
    init(content: String, isUser: Bool, citations: [Citation] = []) {
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
        self.citations = citations
    }
}

struct Citation: Identifiable {
    let id = UUID()
    let pageNumber: Int
    let excerpt: String
    let context: String
}