import SwiftUI

/// The check that decides whether a home workout counts (FLOW, Flow 4).
///
/// The timer ended and the apps unlocked. Apple Health was checked at the
/// timer's end; this screen is what "not found" looks like, plus the one way
/// left to prove the workout: a camera photo taken after the timer started,
/// the same day. It can be added any time until midnight, even after this
/// screen is gone.
///
/// The message never accuses: a missing workout can be a watch that has not
/// synced, or Health read access that was never granted, and Apple will not
/// say which. So the line points at the permission without claiming the user
/// did not train.
///
/// PLACEHOLDER UI: designed in Step 3
struct HomeWorkoutProofView: View {
    /// The app's photo store; camera saves go through it.
    let photos: ProgressPhotoStore?
    let onDone: () -> Void

    @State private var isCapturing = false

    var body: some View {
        MorningScreen(trailingTitle: "Done", trailingAction: onDone) {
            VStack(spacing: 22) {
                HaloedGlyph(systemName: "questionmark.circle.fill", size: 82)
                    .frame(height: 158)

                VStack(spacing: 8) {
                    Text(HomeWorkoutRules.notFoundMessage)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("if the workout is really there, gymlock may not be able to read apple health. check the permission in settings.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                }

                // PLACEHOLDER UI: designed in Step 3
                MorningPrimaryButton(
                    title: "take photo",
                    systemImage: "camera.fill",
                    trailingImage: nil
                ) {
                    isCapturing = true
                }

                Text("camera only, taken after the timer, today. it counts as soon as it is saved to progress.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            EmptyView()
        }
        .fullScreenCover(isPresented: $isCapturing) {
            if let photos {
                ProgressPhotoCaptureSheet(
                    isSaving: photos.isImporting,
                    onApproved: { data, _ in
                        isCapturing = false
                        Task { await photos.add(imageData: data, source: .camera, createdAt: Date()) }
                    },
                    onCancel: { isCapturing = false }
                )
            }
        }
    }
}
