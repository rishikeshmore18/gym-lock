#if DEBUG
import SwiftUI

/// All 89 scenarios in their 15 original sections, each exactly once. One tap
/// selects a scenario and returns; nothing runs from here.
struct DaySimulatorLibraryView: View {
    let selected: SimStep?
    let onPick: (SimStep) -> Void

    @State private var query = ""
    @State private var stageFilter: SimStage?

    init(selected: SimStep?, stage: SimStage?, onPick: @escaping (SimStep) -> Void) {
        self.selected = selected
        self.onPick = onPick
        _stageFilter = State(initialValue: stage)
    }

    private func matches(_ step: SimStep) -> Bool {
        let info = SimCatalog.scenario(for: step)
        if let stageFilter, info.stage != stageFilter { return false }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return [step.label, info.summary, info.expected, step.section, SimCatalog.sectionTitle(step.section)]
            .contains { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    private var visibleSections: [(String, [SimStep])] {
        SimStep.sections.compactMap { section in
            let steps = SimCatalog.steps(inSection: section).filter(matches)
            return steps.isEmpty ? nil : (section, steps)
        }
    }

    var body: some View {
        List {
            if let stageFilter {
                Section {
                    Button {
                        self.stageFilter = nil
                    } label: {
                        HStack {
                            Label("Showing \(stageFilter.title) only", systemImage: stageFilter.symbol)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text("Show all")
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.accent)
                        }
                        .font(.subheadline)
                    }
                    .listRowBackground(Theme.accentWash)
                }
            }

            ForEach(visibleSections, id: \.0) { section, steps in
                Section {
                    ForEach(steps) { step in
                        row(step)
                    }
                } header: {
                    Text("\(SimCatalog.sectionTitle(section)) · \(steps.count)")
                } footer: {
                    if section == SimCatalog.calendarSection {
                        Text("Originally \"freezes and at risk\". Each runs the real freeze calendar on its own date.")
                    }
                }
            }

            if visibleSections.isEmpty {
                Text("No scenario matches \"\(query)\".")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search 89 scenarios")
        .navigationTitle("All Scenarios")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Stage", selection: $stageFilter) {
                        Text("All stages").tag(SimStage?.none)
                        ForEach(SimStage.allCases) { stage in
                            Label(stage.title, systemImage: stage.symbol).tag(SimStage?.some(stage))
                        }
                    }
                } label: {
                    Image(systemName: stageFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("Filter by stage")
            }
        }
    }

    private func row(_ step: SimStep) -> some View {
        let info = SimCatalog.scenario(for: step)
        let isSelected = step == selected
        return Button {
            onPick(step)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(step.label)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(info.summary)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                    Text("\(info.stage.title) · \(info.staysOpen ? "shows a result" : "closes to show the flow")")
                        .font(.caption)
                        .foregroundStyle(Theme.inkTertiary)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.surface)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
