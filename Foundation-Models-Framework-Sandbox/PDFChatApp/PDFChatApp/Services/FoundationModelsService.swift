import Foundation
import FoundationModels
import NaturalLanguage
import CoreML

/// Service for interacting with Apple's Foundation Models Framework
@available(iOS 17.0, *)
class FoundationModelsService {
    private let textEmbedder: NLEmbedding?
    private var documentEmbeddings: [Int: [Double]] = [:]
    
    init() {
        // Initialize the text embedder for semantic search
        self.textEmbedder = NLEmbedding.sentenceEmbedding(for: .english)
    }
    
    /// Process a PDF document and create embeddings for semantic search
    func processDocument(_ document: PDFDocument) async {
        documentEmbeddings.removeAll()
        
        for (pageNumber, content) in document.pageContents {
            if let embedding = generateEmbedding(for: content) {
                documentEmbeddings[pageNumber] = embedding
            }
        }
    }
    
    /// Generate response for a user query based on the document content
    func generateResponse(
        for query: String,
        document: PDFDocument
    ) async throws -> (answer: String, citations: [DocumentCitation]) {
        
        // Find relevant pages using semantic search
        let relevantPages = findRelevantPages(for: query, in: document)
        
        // Build context from relevant pages
        let context = buildContext(from: relevantPages, document: document)
        
        // Generate response using Foundation Models
        let response = try await generateAnswerWithModel(
            query: query,
            context: context
        )
        
        // Extract citations from the relevant pages
        let citations = extractCitations(
            from: response,
            relevantPages: relevantPages,
            document: document
        )
        
        return (answer: response, citations: citations)
    }
    
    private func generateEmbedding(for text: String) -> [Double]? {
        guard let embedder = textEmbedder else { return nil }
        
        // Get embedding vector for the text
        guard let vector = embedder.vector(for: text) else { return nil }
        
        return vector
    }
    
    private func findRelevantPages(
        for query: String,
        in document: PDFDocument,
        topK: Int = 3
    ) -> [(pageNumber: Int, score: Double)] {
        
        guard let queryEmbedding = generateEmbedding(for: query) else {
            // Fallback to simple text search if embeddings fail
            return findPagesWithTextSearch(query: query, document: document)
        }
        
        var pageScores: [(pageNumber: Int, score: Double)] = []
        
        for (pageNumber, pageEmbedding) in documentEmbeddings {
            let similarity = cosineSimilarity(queryEmbedding, pageEmbedding)
            pageScores.append((pageNumber: pageNumber, score: similarity))
        }
        
        // Sort by similarity score and return top K
        return Array(pageScores.sorted { $0.score > $1.score }.prefix(topK))
    }
    
    private func cosineSimilarity(_ vector1: [Double], _ vector2: [Double]) -> Double {
        guard vector1.count == vector2.count else { return 0 }
        
        var dotProduct: Double = 0
        var norm1: Double = 0
        var norm2: Double = 0
        
        for i in 0..<vector1.count {
            dotProduct += vector1[i] * vector2[i]
            norm1 += vector1[i] * vector1[i]
            norm2 += vector2[i] * vector2[i]
        }
        
        guard norm1 > 0 && norm2 > 0 else { return 0 }
        
        return dotProduct / (sqrt(norm1) * sqrt(norm2))
    }
    
    private func findPagesWithTextSearch(
        query: String,
        document: PDFDocument
    ) -> [(pageNumber: Int, score: Double)] {
        
        var results: [(pageNumber: Int, score: Double)] = []
        let queryWords = query.lowercased().split(separator: " ")
        
        for (pageNumber, content) in document.pageContents {
            let lowercasedContent = content.lowercased()
            var matchCount = 0
            
            for word in queryWords {
                if lowercasedContent.contains(word) {
                    matchCount += 1
                }
            }
            
            if matchCount > 0 {
                let score = Double(matchCount) / Double(queryWords.count)
                results.append((pageNumber: pageNumber, score: score))
            }
        }
        
        return results.sorted { $0.score > $1.score }
    }
    
    private func buildContext(
        from relevantPages: [(pageNumber: Int, score: Double)],
        document: PDFDocument
    ) -> String {
        
        var context = "Relevant document excerpts:\n\n"
        
        for (pageNumber, _) in relevantPages {
            if let pageContent = document.pageContents[pageNumber] {
                context += "Page \(pageNumber):\n"
                
                // Truncate if too long
                let maxLength = 1500
                if pageContent.count > maxLength {
                    context += String(pageContent.prefix(maxLength)) + "...\n\n"
                } else {
                    context += pageContent + "\n\n"
                }
            }
        }
        
        return context
    }
    
    private func generateAnswerWithModel(
        query: String,
        context: String
    ) async throws -> String {
        
        // Create the prompt for the model
        let prompt = """
        You are a helpful assistant that answers questions about PDF documents.
        Answer the question based solely on the provided context. If the answer cannot be found in the context, say so clearly.
        Be specific and cite page numbers when referencing information.
        
        Context:
        \(context)
        
        Question: \(query)
        
        Answer:
        """
        
        // In production, this would use the actual Foundation Models API
        // For demonstration, we'll use a structured response
        let answer = """
        Based on the document content, I can help you with your question. \
        The information you're looking for can be found in the provided pages. \
        Let me provide you with a comprehensive answer based on what's in the document.
        """
        
        return answer
    }
    
    private func extractCitations(
        from response: String,
        relevantPages: [(pageNumber: Int, score: Double)],
        document: PDFDocument
    ) -> [DocumentCitation] {
        
        var citations: [DocumentCitation] = []
        
        for (pageNumber, score) in relevantPages where score > 0.3 {
            if let pageContent = document.pageContents[pageNumber] {
                // Extract a relevant excerpt
                let excerpt = extractRelevantExcerpt(
                    from: pageContent,
                    maxLength: 200
                )
                
                citations.append(DocumentCitation(
                    pageNumber: pageNumber,
                    excerpt: excerpt,
                    relevanceScore: score
                ))
            }
        }
        
        return citations
    }
    
    private func extractRelevantExcerpt(
        from text: String,
        maxLength: Int
    ) -> String {
        
        // Find the most relevant sentence or paragraph
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        
        if let firstSentence = sentences.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            let trimmed = firstSentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count <= maxLength {
                return trimmed
            } else {
                return String(trimmed.prefix(maxLength)) + "..."
            }
        }
        
        return String(text.prefix(maxLength)) + "..."
    }
}

struct DocumentCitation {
    let pageNumber: Int
    let excerpt: String
    let relevanceScore: Double
}