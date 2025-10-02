import SwiftUI

#if os(iOS)
struct IOSPrincipalToolbar: ToolbarContent {
    let title: String
    let subtitle: String?
    let isRecording: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 200)
                if let sub = subtitle, !isRecording {
                    Text(sub).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
#endif

