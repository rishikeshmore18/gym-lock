#if DEBUG
import SwiftUI

/// What one run did, read-only. There is no automatic verdict: the scenarios
/// carry no assertions, so the page shows what was expected next to what was
/// observed and leaves the comparison to you.
struct DaySimulatorResultView: View {
    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator

    let step: SimStep
    let ranAt: Date
    let stayMinutes: Int?
    let onRunAnother: () -> Void
    let onDiagnostics: () -> Void

    @State private var resultLine = "none"
    @State private var readAt = Date()

    private var info: SimScenario { SimCatalog.scenario(for: step) }
    private var source: SimReadingSource { SimReadingSource(store: store, coordinator: coordinator) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                card(title: "Scenario") {
                    Text(step.label)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text(info.summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                    SimReadingRow(label: "section", value: SimCatalog.sectionTitle(step.section))
                    SimReadingRow(label: "stage", value: info.stage.title)
                    if let stayMinutes {
                        SimReadingRow(label: "time at gym", value: "\(stayMinutes) min")
                    }
                    SimReadingRow(label: "ran at", value: ranAt.formatted(date: .omitted, time: .standard))
                }

                card(title: "Expected") {
                    Text(info.expected)
                        .font(.body)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                card(title: "Observed") {
                    if let channel = info.resultChannel {
                        Text(channel.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.inkTertiary)
                        Text(resultLine)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Divider()
                    }
                    ForEach(SimCatalog.readings(for: step), id: \.self) { reading in
                        let line = source.value(reading)
                        SimReadingRow(label: line.label, value: line.value)
                    }
                    HStack {
                        Text("Read at \(readAt.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(Theme.inkTertiary)
                        Spacer()
                        Button("Refresh", action: refresh)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }

                Label("Simulation. No automatic pass or fail: compare observed with expected.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.vertical, 18)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Test Result")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button(action: onRunAnother) {
                    Text("Run another test")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.accent, in: .capsule)
                }
                .buttonStyle(.plain)
                Button("View diagnostics", action: onDiagnostics)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Theme.canvas.opacity(0.97).ignoresSafeArea(edges: .bottom))
        }
        .task {
            refresh()
            // Some scenarios finish on a later turn of the run loop (the
            // missing-song ringer, alarm sync), so read once more shortly after.
            try? await Task.sleep(for: .milliseconds(600))
            refresh()
        }
    }

    private func refresh() {
        resultLine = info.resultChannel?.value ?? "none"
        readAt = Date()
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.heavy))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.inkTertiary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard(radius: 18)
    }
}
#endif
