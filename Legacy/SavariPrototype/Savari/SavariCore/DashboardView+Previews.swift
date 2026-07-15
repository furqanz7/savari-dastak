import SwiftUI

struct DashboardViewPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            DashboardView(role: "Passenger")
                .preferredColorScheme(.light)
            DashboardView(role: "Driver")
                .preferredColorScheme(.dark)
        }
    }
}
