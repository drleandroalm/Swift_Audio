import SwiftUI

struct SpeakerRenameView: View {
    let speaker: Speaker
    @Binding var newName: String
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        content
            .frame(width: 420)
        #else
        content
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "pencil")
                    .font(.title3)
                Text("Renomear falante")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Nome atual: \(speaker.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Novo nome", text: $newName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Salvar") {
                    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSave(trimmed)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }
}

