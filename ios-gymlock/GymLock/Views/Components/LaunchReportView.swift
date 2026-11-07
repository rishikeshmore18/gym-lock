import SwiftUI
import UIKit

/// Temporary: shown instead of the app when the previous launch did not finish (see CrashSentinel).
struct LaunchReportView: View {
    let report: String
    let onContinue: (_ heroSafeMode: Bool) -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("last launch stopped")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(.white)
                Text("copy this report and send it in the chat")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.6))
            }
            ScrollView {
                Text(report)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                UIPasteboard.general.string = report
                copied = true
            } label: {
                Text(copied ? "copied" : "copy report")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)

            HStack(spacing: 20) {
                Button("open app") { onContinue(false) }
                Button("open without hero painting") { onContinue(true) }
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white.opacity(0.75))
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
