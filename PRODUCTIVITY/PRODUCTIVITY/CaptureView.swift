import SwiftUI

struct CaptureView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var draft: String = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $draft)
                .textEditorStyle(.plain)
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
                }
        }
    }
}
