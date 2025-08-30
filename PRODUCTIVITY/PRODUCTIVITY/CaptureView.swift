import SwiftUI

struct CaptureView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var draft: String = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $draft)
                .textEditorStyle(.plain)
                .focused($isEditing)
                .scrollContentBackground(.hidden)
                .padding()
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Notes")
                            .font(.title).bold()
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Send to Lists") {
                            store.importFromText(draft)
                            draft = ""
                        }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { isEditing = false }
                    }
                }
                .onAppear { isEditing = true }
        }
    }
}
