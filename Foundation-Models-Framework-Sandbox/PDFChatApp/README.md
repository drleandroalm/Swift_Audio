# PDF Chat Assistant for iOS

An intelligent iOS/iPadOS application that enables natural language interaction with PDF documents using Apple's Foundation Models Framework.

## Features

- **PDF Document Support**: Select PDFs from iCloud or upload directly into the app
- **Natural Language Processing**: Ask questions about your PDF content in plain English
- **Smart Citations**: Automatic page references and excerpts for every answer
- **Semantic Search**: Advanced embedding-based search for finding relevant content
- **Universal Compatibility**: Optimized for both iOS 17+ and iPadOS 17+
- **Beautiful UI**: Modern, intuitive interface with smooth animations

## System Requirements

- iOS 17.0+ / iPadOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## Architecture

### Core Components

1. **PDFDocumentManager**: Handles PDF loading and processing
2. **ChatManager**: Manages the conversation flow and message history
3. **FoundationModelsService**: Integrates with Apple's Foundation Models for NLP
4. **Document Embeddings**: Creates semantic embeddings for intelligent search

### Key Technologies

- **SwiftUI**: Modern declarative UI framework
- **PDFKit**: Native PDF rendering and text extraction
- **Foundation Models Framework**: Apple's on-device language models
- **NaturalLanguage Framework**: Text embeddings and semantic analysis

## Setup Instructions

1. Clone the repository:
```bash
git clone <repository-url>
cd PDFChatApp
```

2. Open the project in Xcode:
```bash
open PDFChatApp.xcodeproj
```

3. Configure your development team:
   - Select the project in Xcode
   - Go to "Signing & Capabilities"
   - Select your development team

4. Enable iCloud capabilities:
   - In "Signing & Capabilities", click "+"
   - Add "iCloud" capability
   - Enable "iCloud Documents"

5. Build and run:
   - Select your target device (iPhone/iPad)
   - Press Cmd+R to build and run

## Usage

1. **Loading a PDF**:
   - Tap the menu icon in the top-right corner
   - Choose "Select from iCloud" or "Upload PDF"
   - Select your document

2. **Asking Questions**:
   - Type your question in the input field
   - Press send or hit return
   - The AI will analyze the PDF and provide an answer with citations

3. **Viewing Citations**:
   - Tap on the citations link below an answer
   - View the exact page references and excerpts

## Project Structure

```
PDFChatApp/
├── PDFChatApp.swift          # Main app entry point
├── ContentView.swift         # Primary view controller
├── Models/
│   ├── PDFDocument.swift    # PDF document model
│   └── ChatMessage.swift    # Chat message and citation models
├── Managers/
│   ├── PDFDocumentManager.swift  # PDF handling logic
│   └── ChatManager.swift         # Chat session management
├── Services/
│   └── FoundationModelsService.swift  # AI/ML service layer
├── Views/
│   ├── ChatView.swift       # Chat interface components
│   └── DocumentPicker.swift # iCloud document picker
└── Assets.xcassets/         # App resources and icons
```

## Advanced Features

### Semantic Search
The app uses advanced embedding techniques to find relevant content:
- Generates embeddings for each page of the PDF
- Calculates cosine similarity between query and page embeddings
- Returns the most relevant pages for context

### Citation System
Every answer includes:
- Page numbers where information was found
- Relevant excerpts from those pages
- Confidence scores for each citation

### Performance Optimization
- Lazy loading of PDF content
- Efficient text extraction and caching
- Optimized embedding generation

## Privacy & Security

- All processing happens on-device using Apple's Foundation Models
- No data is sent to external servers
- PDFs remain private and secure
- iCloud integration uses Apple's secure infrastructure

## Troubleshooting

### PDF Not Loading
- Ensure the PDF contains extractable text (not scanned images)
- Check file permissions for iCloud documents
- Verify the PDF is not password-protected

### Slow Response Times
- Large PDFs may take longer to process initially
- First query creates embeddings (cached for subsequent queries)
- Consider breaking very large PDFs into smaller sections

## Future Enhancements

- [ ] Support for multiple PDFs simultaneously
- [ ] Export conversation history
- [ ] Highlighting in PDF viewer
- [ ] Support for additional document formats
- [ ] Offline mode improvements
- [ ] Custom model fine-tuning

## License

This project is provided as-is for educational and development purposes.

## Support

For issues or questions, please file an issue in the repository.