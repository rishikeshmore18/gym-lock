#if DEBUG
import SwiftUI

/// Debug-only lab for the Dynamic hero card.
///
/// Renders any of the 19 moments in any of the 7 themes, light or dark, as
/// the live card (entrance, beat, idle loop, haptics) or as one deterministic
/// frame at a chosen T (the same harness the web parity images use). It also
/// runs the Matrix parity self-tests on the device, so the port can be checked
/// against the TypeScript golden values without a test run.
///
/// The whole file is inside `#if DEBUG`; none of it ships.
struct HeroCardLabView: View {
    /// Theme index 0...6, the columns of `mx/*.ts` SCENES (02-experience-spec §1).
    static let themeNames = ["radiant", "tiles", "signal", "levels", "vectors", "loops", "week"]

    enum Mode: String, CaseIterable, Identifiable {
        case live = "Live"
        case frame = "Frame at T"
        var id: String { rawValue }
    }

    enum Scheme: String, CaseIterable, Identifiable {
        case light = "Light"
        case dark = "Dark"
        var id: String { rawValue }
        var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    }

    @State private var moment: MatrixMoment = .verified
    @State private var theme = 2
    @State private var pos: MatrixWeekPos = .middle
    @State private var scheme: Scheme = .light
    @State private var mode: Mode = .live
    @State private var hapticsOn = true
    @State private var habitDay = 23
    @State private var sessions = 14

    /// Live mode restarts when this changes (a fresh card, fresh clocks).
    @State private var replay = 0
    @State private var replayStarted = Date()

    /// Frame mode: the slider position, and the T actually rendered (set on release,
    /// because every frame re-simulates the board from T = 0).
    @State private var sliderT: Double = 1
    @State private var frameT: Double = 1

    @State private var parity: ParityState = .idle

    enum ParityState: Equatable {
        case idle
        case running
        case done(failures: [String], seconds: Double)
    }

    var body: some View {
        List {
            Section {
                preview
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    .listRowBackground(scheme == .dark ? Color.black : Theme.canvas)
            } footer: {
                Text(statusLine)
            }

            Section("Card") {
                Picker("Moment", selection: $moment) {
                    ForEach(MatrixMoment.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                Picker("Theme", selection: $theme) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(themeLabel(i)).tag(i)
                    }
                }
                Picker("Week position", selection: $pos) {
                    ForEach(MatrixWeekPos.allCases, id: \.self) { p in
                        Text(p.rawValue.capitalized).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Appearance", selection: $scheme) {
                    ForEach(Scheme.allCases) { s in Text(s.rawValue).tag(s) }
                }
                .pickerStyle(.segmented)
                Stepper("Habit day \(habitDay)", value: $habitDay, in: 1...66)
                Stepper("Sessions so far \(sessions)", value: $sessions, in: 0...66)
            }

            Section("Playback") {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
                }
                .pickerStyle(.segmented)

                if mode == .live {
                    Toggle("Haptics", isOn: $hapticsOn)
                    Button("Replay entrance") { restart() }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("T = \(sliderT, specifier: "%.2f") s")
                            .font(.system(.subheadline, design: .monospaced))
                        Slider(value: $sliderT, in: 0...12, step: 0.05) { editing in
                            if !editing { frameT = sliderT }
                        }
                    }
                }
            }

            Section {
                Button {
                    runParity()
                } label: {
                    HStack {
                        Text("Run Matrix parity")
                        Spacer()
                        if parity == .running { ProgressView() }
                    }
                }
                .disabled(parity == .running)
                parityResult
            } header: {
                Text("Parity")
            } footer: {
                Text("Engine, board helpers and the ported scenes, checked against the TypeScript golden values (hash 1e-11, checksums 1e-9, engine 1e-5).")
            }
        }
        .navigationTitle("Hero card lab")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: moment) { _, _ in restart() }
        .onChange(of: theme) { _, _ in restart() }
        .onChange(of: pos) { _, _ in restart() }
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        Group {
            switch mode {
            case .live:
                MatrixCardView(input: liveInput)
                    .id(replay)
            case .frame:
                frame
            }
        }
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
        .environment(\.colorScheme, scheme.colorScheme)
    }

    /// The 600 x 293 harness frame, scaled to the row width.
    private var frame: some View {
        GeometryReader { proxy in
            MatrixHarnessFrame(
                moment: moment,
                day: theme,
                T: frameT,
                look: MatrixLook.resolve(moment, scheme.colorScheme),
                pos: pos,
                dayData: dayData
            )
            .scaleEffect(proxy.size.width / 600, anchor: .topLeading)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .aspectRatio(MatrixCardGeometry.aspect, contentMode: .fit)
    }

    private var dayData: MatrixDayData {
        MatrixDayData(day: habitDay, week: (habitDay - 1) / 7 + 1, sessions: sessions)
    }

    private var liveInput: MatrixCardInput {
        let start = replayStarted
        let clock = MatrixLiveClock(
            setupDone: [true, true, false],
            countdownEnd: start.addingTimeInterval(40 * 60 + 12),
            gymStart: start.addingTimeInterval(-(9 * 60 + 30)),
            eveningEnd: start.addingTimeInterval(2.4 * 3600)
        )
        return MatrixCardInput(
            moment: moment,
            day: theme,
            pos: pos,
            dayData: dayData,
            clock: clock,
            copy: labCopy,
            entrance: .onAppear,
            hapticsEnabled: hapticsOn
        )
    }

    /// Stand-in words so the copy column has the right shape. The real lines
    /// come from the copy tables when the resolver is wired (build step 5).
    private var labCopy: MatrixCardCopy {
        let eyebrow = moment.rawValue.capitalized
        switch moment {
        case .countdown:
            return MatrixCardCopy(eyebrow: "Leave in", headline: .countdownClock, support: "Shoes by the door. Keys in hand.")
        case .atgym:
            return MatrixCardCopy(eyebrow: "At the gym", headline: .plain("09:30"), support: "**{left}** to go. Twenty minutes makes it count.", liveDot: true, showsProofBar: true)
        case .stilltime:
            return MatrixCardCopy(eyebrow: "Still time", headline: .text("There's still tonight", .rise), support: "The gym is open until 22:00.", liveDot: true)
        default:
            let styles = MatrixKineticStyle.allCases
            let style = styles[(MatrixMoment.allCases.firstIndex(of: moment) ?? 0) % styles.count]
            return MatrixCardCopy(eyebrow: eyebrow, headline: .text("\(Self.themeNames[theme].capitalized) preview", style), support: "Lab copy. Day \(habitDay), \(sessions) sessions.")
        }
    }

    private func themeLabel(_ i: Int) -> String {
        let ported = MatrixSceneRegistry.isPorted(moment, day: i)
        return "\(i) \(Self.themeNames[i])" + (ported ? "" : " (not ported)")
    }

    private var statusLine: String {
        var ported = 0
        for m in MatrixMoment.allCases {
            for i in 0..<7 where MatrixSceneRegistry.isPorted(m, day: i) { ported += 1 }
        }
        let here = MatrixSceneRegistry.isPorted(moment, day: theme) ? "ported" : "not ported yet, the board stays empty"
        return "\(moment.rawValue) · \(Self.themeNames[theme]): \(here). \(ported) of 133 scenes ported."
    }

    private func restart() {
        replayStarted = Date()
        replay += 1
    }

    // MARK: - Parity

    @ViewBuilder
    private var parityResult: some View {
        switch parity {
        case .idle, .running:
            EmptyView()
        case .done(let failures, let seconds):
            if failures.isEmpty {
                Label("All checks match (\(seconds, specifier: "%.2f") s)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("\(failures.count) mismatches", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(Theme.accent)
                ForEach(Array(failures.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func runParity() {
        parity = .running
        Task { @MainActor in
            // Let the spinner draw before the synchronous run.
            try? await Task.sleep(for: .milliseconds(50))
            let start = Date()
            let failures = MatrixParity.run() + MatrixParity.runStory() + MatrixParity.runAll()
            parity = .done(failures: failures, seconds: Date().timeIntervalSince(start))
        }
    }
}

#Preview {
    NavigationStack { HeroCardLabView() }
}
#endif
