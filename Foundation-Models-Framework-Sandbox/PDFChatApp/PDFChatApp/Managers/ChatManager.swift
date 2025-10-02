import Foundation
import SwiftUI

@MainActor
class ChatManager: ObservableObject {
    @Published var messages: [ChatMessage] = []
    private let modelService = FoundationModelsService()
    
    func processQuery(_ query: String, with document: PDFDocument?) async {
        guard let document = document else { return }
        
        // Add user message
        messages.append(ChatMessage(content: query, isUser: true))
        
        // Process the document if not already done
        await modelService.processDocument(document)
        
        // Process with Foundation Models Framework
        do {
            let (answer, documentCitations) = try await modelService.generateResponse(
                for: query,
                document: document
            )
            
            // Convert DocumentCitation to Citation
            let citations = documentCitations.map { docCitation in
                Citation(
                    pageNumber: docCitation.pageNumber,
                    excerpt: docCitation.excerpt,
                    context: docCitation.excerpt
                )
            }
            
            // Add AI response with citations
            messages.append(ChatMessage(
                content: answer,
                isUser: false,
                citations: citations
            ))
        } catch {
            messages.append(ChatMessage(
                content: "I'm sorry, I encountered an error processing your request. Please try again.",
                isUser: false
            ))
        }
    }
    
    func clearChat() {
        messages.removeAll()
    }
}