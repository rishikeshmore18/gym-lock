import SwiftUI

/// Asks what to do when a day already has a progress photo.
///
/// The rule is one photo per day, and the question only has two honest answers:
/// the new photo takes the day, or it does not. "Delete the old one" and "use
/// the new one instead" are the same outcome described twice, and offering both
/// would make the user stop and work out whether they differ — so the choice is
/// presented as the single decision it actually is.
///
/// A confirmation dialog rather than an alert: this is a choice between courses
/// of action, not a warning, and the destructive option can carry its role and
/// be styled by the system.
struct ProgressPhotoDayConflict: ViewModifier {
    let store: ProgressPhotoStore

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: Binding(
                get: { store.pending != nil },
                // Dismissing by tapping outside keeps what is already saved,
                // which is the safe reading of walking away.
                set: { if !$0 { store.discardPending() } }
            ),
            titleVisibility: .visible,
            presenting: store.pending
        ) { _ in
            Button("Replace Photo", role: .destructive) {
                Task { await store.replacePending() }
            }
            Button("Keep Existing Photo", role: .cancel) {
                store.discardPending()
            }
        } message: { pending in
            Text(
                "You already have a photo from \(pending.dayDescription). "
                    + "Progress Photos keeps one photo per day."
            )
        }
    }

    private var title: String {
        guard let pending = store.pending else { return "Photo already added" }
        return "You've already added a photo for \(pending.dayDescription)"
    }
}

extension View {
    /// Attaches the one-photo-per-day prompt.
    func progressPhotoDayConflict(store: ProgressPhotoStore) -> some View {
        modifier(ProgressPhotoDayConflict(store: store))
    }
}
