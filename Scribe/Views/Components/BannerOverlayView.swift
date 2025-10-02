import SwiftUI

struct BannerOverlayView: View {
    let isVisible: Bool
    let message: String?

    var body: some View {
        Group {
            if isVisible, let msg = message {
                VStack {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        Text(msg).font(.subheadline).fontWeight(.semibold)
                    }
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(radius: 4)
                    Spacer()
                }
                .padding(.top, 16)
            }
        }
    }
}

