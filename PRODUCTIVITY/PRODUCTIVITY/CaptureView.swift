import SwiftUI

struct CaptureView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var draft: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextEditor(text: $draft)
                    .font(.body)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                    .padding(.horizontal)
                    .frame(minHeight: 220)

                HStack {
                    Button("Clear") { draft = "" }
                        .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        store.importFromText(draft)
                        draft = ""
                    } label: {
                        Label("Add Tasks", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)

                HelpLine()
            }
            .navigationTitle("Capture")
        }
    }
}

private struct HelpLine: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tips")
                .font(.headline)
            Text("""
Each line becomes a task. Use #tags and optional durations like:
  • Finish essay #school [45m]
  • Call dentist #errands [1h]
""").foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }
}
