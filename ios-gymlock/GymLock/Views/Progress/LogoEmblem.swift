import SwiftUI

/// The badges emblem: the GymLock mark, desaturated.
///
/// Badges do not exist yet, so there is nothing earned to draw — the mark shows
/// up in grey for the same reason an unrecorded day stays blank. The moment a
/// real badge system lands, this is the slot it renders into.
struct LogoEmblem: View {
    var body: some View {
        Image("GymLockLogo")
            .resizable()
            .scaledToFit()
            .frame(height: 78)
            .saturation(0)
            .opacity(0.88)
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }
}

#Preview {
    LogoEmblem()
        .padding(40)
        .background(Theme.surface)
}
