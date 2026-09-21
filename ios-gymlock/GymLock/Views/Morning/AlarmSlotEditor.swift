import SwiftUI

/// Edits one recurring alarm.
///
/// Extracted from `MorningAlarmPlanView` so both the morning plan screen and
/// the alarm settings screen open the identical editor, rather than one of
/// them growing a near-copy that drifts.
struct AlarmSlotEditor: View {
    let slot: AlarmSlot
    let onSave: (AlarmSlot) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: AlarmSlot

    init(slot: AlarmSlot, onSave: @escaping (AlarmSlot) -> Void, onDelete: @escaping () -> Void) {
        self.slot = slot
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: slot)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        TimeWheel(time: $draft.alarmTime, accessibilityTitle: "Alarm time")
                            .padding(.top, 8)

                        dayPicker

                        if !draft.daypart.usesSleepRhythm {
                            eveningNote
                        }

                        Button(role: .destructive) {
                            Haptics.tap()
                            onDelete()
                            dismiss()
                        } label: {
                            Text("delete this alarm")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .tint(Theme.accent)
                    }
                    .padding(.horizontal, Theme.pageMargin)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("cancel") { dismiss() }
                        .foregroundStyle(Theme.inkSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("save") {
                        Haptics.tap()
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var dayPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("repeats")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(Weekday.allCases) { day in
                    let isOn = draft.days.contains(day)

                    Button {
                        if isOn { draft.days.remove(day) } else { draft.days.insert(day) }
                        Haptics.selection()
                    } label: {
                        Text(String(day.shortLabel.prefix(1)))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isOn ? .white : Theme.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(
                                isOn ? Theme.accent : Theme.surfaceMuted,
                                in: .rect(cornerRadius: 12)
                            )
                    }
                    .accessibilityLabel(day.shortLabel)
                    .accessibilityAddTraits(isOn ? [.isSelected] : [])
                }
            }
        }
    }

    /// A session outside the morning simply does not use the sleep coupling,
    /// and says so rather than silently ignoring it.
    private var eveningNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)

            Text("this is an \(draft.daypart.label) session, so it uses your prepare and travel window — not your sleep schedule.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceMuted, in: .rect(cornerRadius: 14))
    }
}
