import SwiftUI

struct FinishedMemoContentView: View {
    let header: AnyView
    let toolbar: AnyView
    let modeView: AnyView

    var body: some View {
        VStack(spacing: 0) {
            header
            toolbar
            modeView
        }
    }
}

