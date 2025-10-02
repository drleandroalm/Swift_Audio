import SwiftUI

@main
struct PDFChatApp: App {
    @StateObject private var documentManager = PDFDocumentManager()
    @StateObject private var chatManager = ChatManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(documentManager)
                .environmentObject(chatManager)
        }
    }
}