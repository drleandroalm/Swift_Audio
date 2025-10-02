import Foundation
import PDFKit
import SwiftUI

@MainActor
class PDFDocumentManager: ObservableObject {
    @Published var currentDocument: PDFDocument?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func loadPDF(from url: URL) {
        isLoading = true
        errorMessage = nil
        
        // Start accessing security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        guard let pdfDocument = PDFKit.PDFDocument(url: url) else {
            errorMessage = "Failed to load PDF document"
            isLoading = false
            return
        }
        
        currentDocument = PDFDocument(url: url, pdfDocument: pdfDocument)
        isLoading = false
    }
    
    func clearDocument() {
        currentDocument = nil
        errorMessage = nil
    }
}