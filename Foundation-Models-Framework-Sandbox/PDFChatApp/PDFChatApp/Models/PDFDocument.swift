import Foundation
import PDFKit

struct PDFDocument: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
    let pageCount: Int
    let fileSize: Int64
    let content: String
    let pageContents: [Int: String]
    let pdfDocument: PDFKit.PDFDocument
    
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    init(url: URL, pdfDocument: PDFKit.PDFDocument) {
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
        self.pdfDocument = pdfDocument
        self.pageCount = pdfDocument.pageCount
        
        // Get file size
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
            self.fileSize = attributes[.size] as? Int64 ?? 0
        } else {
            self.fileSize = 0
        }
        
        // Extract text content from all pages
        var fullContent = ""
        var pageContentsDict: [Int: String] = [:]
        
        for pageIndex in 0..<pdfDocument.pageCount {
            if let page = pdfDocument.page(at: pageIndex),
               let pageContent = page.string {
                pageContentsDict[pageIndex + 1] = pageContent // 1-indexed for user-facing page numbers
                fullContent += "Page \(pageIndex + 1):\n\(pageContent)\n\n"
            }
        }
        
        self.content = fullContent
        self.pageContents = pageContentsDict
    }
}