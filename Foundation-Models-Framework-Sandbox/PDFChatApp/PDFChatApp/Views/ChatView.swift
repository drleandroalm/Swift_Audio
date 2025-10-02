import SwiftUI

struct ChatView: View {
    let messages: [ChatMessage]
    @Binding var currentQuery: String
    @Binding var isProcessing: Bool
    let onSend: () -> Void
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        if isProcessing {
                            ProcessingIndicator()
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    withAnimation {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
            }
            
            Divider()
            
            // Input area
            HStack(spacing: 12) {
                TextField("Ask a question about the PDF...", text: $currentQuery)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isInputFocused)
                    .onSubmit {
                        if !currentQuery.isEmpty {
                            onSend()
                        }
                    }
                
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(currentQuery.isEmpty ? .gray : .accentColor)
                }
                .disabled(currentQuery.isEmpty || isProcessing)
            }
            .padding()
            .background(Color(UIColor.systemBackground))
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    @State private var showingCitations = false
    
    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
            HStack {
                if message.isUser {
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.content)
                        .padding(12)
                        .background(message.isUser ? Color.accentColor : Color(UIColor.secondarySystemBackground))
                        .foregroundColor(message.isUser ? .white : .primary)
                        .cornerRadius(16)
                    
                    if !message.citations.isEmpty {
                        Button(action: { showingCitations.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "quote.bubble")
                                    .font(.caption)
                                Text("\(message.citations.count) citation\(message.citations.count > 1 ? "s" : "")")
                                    .font(.caption)
                            }
                            .foregroundColor(.accentColor)
                        }
                        .padding(.leading, 12)
                    }
                }
                .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: .leading)
                
                if !message.isUser {
                    Spacer()
                }
            }
            
            if showingCitations {
                CitationsView(citations: message.citations)
                    .padding(.top, 4)
            }
        }
    }
}

struct CitationsView: View {
    let citations: [Citation]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(citations) { citation in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.caption)
                        Text("Page \(citation.pageNumber)")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.accentColor)
                    
                    Text(citation.excerpt)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .padding(8)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(8)
                }
            }
        }
        .frame(maxWidth: UIScreen.main.bounds.width * 0.75)
    }
}

struct ProcessingIndicator: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}