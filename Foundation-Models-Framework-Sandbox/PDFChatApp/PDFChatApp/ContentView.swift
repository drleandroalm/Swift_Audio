import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var documentManager: PDFDocumentManager
    @EnvironmentObject var chatManager: ChatManager
    @State private var showingDocumentPicker = false
    @State private var showingFilePicker = false
    @State private var currentQuery = ""
    @State private var isProcessing = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with PDF info
                if let document = documentManager.currentDocument {
                    PDFInfoHeader(document: document)
                        .padding()
                        .background(Color(UIColor.systemBackground))
                        .shadow(radius: 2)
                } else {
                    WelcomeView(
                        showingDocumentPicker: $showingDocumentPicker,
                        showingFilePicker: $showingFilePicker
                    )
                }
                
                // Chat interface
                if documentManager.currentDocument != nil {
                    ChatView(
                        messages: chatManager.messages,
                        currentQuery: $currentQuery,
                        isProcessing: $isProcessing,
                        onSend: sendMessage
                    )
                }
                
                Spacer()
            }
            .navigationTitle("PDF Chat Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showingDocumentPicker = true }) {
                            Label("Select from iCloud", systemImage: "icloud")
                        }
                        Button(action: { showingFilePicker = true }) {
                            Label("Upload PDF", systemImage: "doc.badge.plus")
                        }
                        if documentManager.currentDocument != nil {
                            Divider()
                            Button(action: { documentManager.clearDocument() }) {
                                Label("Close PDF", systemImage: "xmark.circle")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker(documentManager: documentManager)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [UTType.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    documentManager.loadPDF(from: url)
                }
            case .failure(let error):
                print("Error selecting file: \(error)")
            }
        }
    }
    
    private func sendMessage() {
        guard !currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isProcessing = true
        let query = currentQuery
        currentQuery = ""
        
        Task {
            await chatManager.processQuery(query, with: documentManager.currentDocument)
            await MainActor.run {
                isProcessing = false
            }
        }
    }
}

struct WelcomeView: View {
    @Binding var showingDocumentPicker: Bool
    @Binding var showingFilePicker: Bool
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
            
            Text("Welcome to PDF Chat")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Select or upload a PDF to start asking questions")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(spacing: 15) {
                Button(action: { showingDocumentPicker = true }) {
                    HStack {
                        Image(systemName: "icloud")
                        Text("Select from iCloud")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                Button(action: { showingFilePicker = true }) {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                        Text("Upload PDF")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundColor(.accentColor)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.accentColor, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }
}

struct PDFInfoHeader: View {
    let document: PDFDocument
    
    var body: some View {
        HStack {
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading) {
                Text(document.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Text("\(document.pageCount) pages • \(document.formattedFileSize)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PDFDocumentManager())
        .environmentObject(ChatManager())
}