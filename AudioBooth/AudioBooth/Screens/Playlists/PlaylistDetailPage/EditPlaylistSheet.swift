import SwiftUI

struct EditPlaylistSheet: View {
  @Environment(\.dismiss) var dismiss
  @State private var name: String
  @State private var description: String
  @FocusState private var focusedField: Field?

  let onSave: (String, String) -> Void

  enum Field {
    case name
    case description
  }

  init(name: String, description: String, onSave: @escaping (String, String) -> Void) {
    self._name = State(initialValue: name)
    self._description = State(initialValue: description)
    self.onSave = onSave
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Playlist Name", text: $name)
            .focused($focusedField, equals: .name)
        } header: {
          Text("Name")
        }

        Section {
          TextField("Description (optional)", text: $description, axis: .vertical)
            .lineLimit(3...6)
            .focused($focusedField, equals: .description)
        } header: {
          Text("Description")
        }
      }
      .navigationTitle("Edit Playlist")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            guard !trimmedName.isEmpty else { return }
            onSave(trimmedName, description.trimmingCharacters(in: .whitespaces))
            dismiss()
          }
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      .onAppear {
        focusedField = .name
      }
    }
    .presentationDetents([.medium])
  }
}

#Preview {
  EditPlaylistSheet(
    name: "My Favorites",
    description: "My favorite audiobooks to listen to",
    onSave: { name, description in
      print("Name: \(name)")
      print("Description: \(description)")
    }
  )
}
