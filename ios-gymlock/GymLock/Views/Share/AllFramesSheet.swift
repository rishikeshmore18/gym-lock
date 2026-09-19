import SwiftUI

/// The full frame gallery, over the editor.
///
/// A sheet rather than a push so the editor stays visible behind it and a
/// selection made here is seen taking effect immediately. Three filters,
/// because eight frames do not need a taxonomy. Locked frames show what they
/// would be and what unlocks them; Comeback is never among them.
struct AllFramesSheet: View {
    @Bindable var model: StoryEditorModel
    let onSelect: (ShareFrame) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all, available, locked
        var id: String { rawValue }
    }

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    /// What the current filter shows, in `allCases` order. Not-today frames
    /// are never listed: nothing is locked, they simply do not apply here.
    private var entries: [(frame: ShareFrame, state: FrameAvailability)] {
        model.availability.filter { entry in
            switch (filter, entry.state) {
            case (.all, .available), (.all, .locked), (.available, .available), (.locked, .locked): true
            default: false
            }
        }
    }

    private var emptyMessage: String? {
        guard entries.isEmpty || (filter == .available && entries.count == 1 && entries.first?.frame == .clean) else {
            return nil
        }
        switch filter {
        case .locked: return "everything is unlocked."
        case .available: return "more frames appear as your record grows."
        case .all: return "nothing to show for this day yet."
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    GlassSegmentedControl(
                        options: Filter.allCases,
                        selected: filter,
                        title: { $0.rawValue },
                        onSelect: { filter = $0 }
                    )
                    grid
                    if let emptyMessage {
                        Text(emptyMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.top, entries.isEmpty ? 40 : 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 110)
            }

            useButton
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .background(sheetBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Frames")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                Text("turn your progress into a story")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            EditorCloseButton { dismiss() }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(entries, id: \.frame) { entry in
                card(entry.frame, state: entry.state)
            }
        }
    }

    private func card(_ frame: ShareFrame, state: FrameAvailability) -> some View {
        let isSelected = frame == model.frame && state == .available
        let lock = state.lock
        return Button {
            guard state == .available else { return }
            onSelect(frame)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { proxy in
                    let size = CGSize(width: proxy.size.width, height: proxy.size.width / model.format.ratio)
                    FrameThumbnail(model: model, frame: frame, isLocked: lock != nil, size: size, cornerRadius: 14)
                        .modifier(ConditionalLock(isLocked: lock != nil))
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.accent, lineWidth: 2)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white, Theme.accent)
                                    .padding(8)
                            }
                        }
                }
                .aspectRatio(model.format.ratio, contentMode: .fit)

                Text(frame.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(lock == nil ? .white : .white.opacity(0.7))
                if let lock {
                    Text(lock.requirement)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.55))
                    if let progress = lock.progress {
                        Text(progress)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                } else {
                    Text(frame.description)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lock == nil ? "\(frame.title) frame" : "\(frame.title) frame, locked")
        .accessibilityHint(lock.map { [$0.requirement, $0.progress].compactMap { $0 }.joined(separator: ", ") } ?? frame.description)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// One place to leave from. Sharing stays in the editor.
    @ViewBuilder
    private var useButton: some View {
        let label = Text("use this frame")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)

        if #available(iOS 26.0, *) {
            Button { dismiss() } label: { label }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(Theme.accent)
        } else {
            Button { dismiss() } label: { label.background(Theme.accent, in: .capsule) }
                .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var sheetBackground: some View {
        if reduceTransparency {
            Color(white: 0.08)
        } else if #available(iOS 26.0, *) {
            Rectangle().fill(.clear).glassEffect(.regular, in: .rect)
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}

private struct ConditionalLock: ViewModifier {
    let isLocked: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isLocked {
            content.modifier(LockedTreatment(symbolSize: 24))
        } else {
            content
        }
    }
}
