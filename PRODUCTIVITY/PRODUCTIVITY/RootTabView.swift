import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            CaptureView()
                .tabItem { Label("Notes", systemImage: "square.and.pencil") }

            ListsView()
                .tabItem { Label("Lists", systemImage: "checklist") }

            TimeboxView()
                .tabItem { Label("Timebox", systemImage: "calendar.badge.clock") }
        }
    }
}
