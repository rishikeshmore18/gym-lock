//
//  Day0PauseStage.swift
//  GymLock · the "plans changed" pause · Day 0 look
//
//  Plays at the worst moment to skip (PauseFacts.isCritical), whatever the card style. The user's own
//  day 0 video or photo sits full bleed behind five beats (where you are, your own words, what is on
//  the line, the 66 visits, the way forward), then the three doors one at a time. Port of the approved
//  prototype docs/prototypes (v-day0.html).
//
//  Everything drawn is a pure function of `input.t` and `input.phase`. The only @State is real state:
//  the loaded photo, the video player and the mute switch. The host owns the close button, pips and
//  every button; this file draws none of them (the small mute toggle is the one control of its own).
//

import AVFoundation
import SwiftUI
import UIKit

// MARK: - Small time helpers (the prototype's prog / ease)

private func day0Prog(_ t: Double, _ start: Double, _ duration: Double) -> Double {
    min(1, max(0, (t - start) / duration))
}

private func day0Ease(_ p: Double) -> Double {
    1 - pow(1 - p, 3)
}

// MARK: - The stage

struct Day0PauseStage: View {
    let input: PauseStageInput

    @State private var holder = Day0PauseVideoHolder()
    @State private var photo: UIImage?
    @State private var isMuted = true

    private static let surface = Color(red: 0.043, green: 0.043, blue: 0.047)

    var body: some View {
        let layout = input.layout
        let beats = Day0PauseBeat.build(script: input.script)
        let cur = currentIndex(beats)
        // How far the doors have taken over from the beats (0 while waiting, 1 once a door shows).
        let doorAge = input.choice?.age ?? 0
        let handover = input.choice == nil ? 0.0 : day0Prog(doorAge, 0, 0.4)
        let k = min(1, max(0.8, layout.contentHeight / 540))
        // With their own video or photo behind, the words sit low as a lower-third (the prototype's #lt)
        // instead of the five full-screen beats. Without media the beats play exactly as before.
        let hasMedia = input.facts.day0 != nil
        let _ = fireHaptics(beats, cur, hasMedia: hasMedia)

        ZStack(alignment: .topLeading) {
            Self.surface

            if input.facts.day0 != nil {
                mediaLayer
            }

            topChrome(handover: handover)

            if !hasMedia, cur >= 0, handover < 1 {
                beatsLayer(beats: beats, cur: cur, k: k)
                    .opacity(1 - handover)
            }

            if hasMedia, handover < 1 {
                lowerThirdLayer()
                    .opacity(1 - handover)
            }

            if let choice = input.choice {
                doorsLayer(choice: choice.choice, index: choice.index, age: choice.age, from: choice.from, k: k)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .clipped()
        .onAppear { startVideo() }
        .onDisappear { holder.stop() }
        .onChange(of: input.isReady) { _, ready in
            if ready { holder.pause() }
        }
        .task(id: input.facts.day0?.fileName) { await loadPhoto() }
    }

    // MARK: Media

    /// The media plays at full strength (the face stays clear, the words sit low), and dims to 50%
    /// once the 30 seconds are up (over 400 ms), like the prototype's `#app.vid #media` and `.dark`.
    private var mediaOpacity: Double {
        1 - 0.5 * day0Prog(input.t, PauseScript.wait, 0.4)
    }

    @ViewBuilder
    private var mediaLayer: some View {
        let size = input.layout.size
        ZStack {
            if let media = input.facts.day0 {
                switch media.kind {
                case .video:
                    Day0PausePlayerView(player: holder.player)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                case .photo:
                    if let photo {
                        // A slow push over the 30 seconds, time-based. Reduce Motion holds it still.
                        let growth = input.reduceMotion ? 0.0 : 0.08 * min(input.t, PauseScript.wait) / PauseScript.wait
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .clipped()
                            .scaleEffect(CGFloat(1 + growth))
                            .transition(.opacity)
                    }
                }
            }
            // The prototype's #vig: a shade at the top for the progress bar and label, clear over the
            // face, then a deep shade low where the lower-third sits.
            LinearGradient(
                gradient: Gradient(stops: [
                    Gradient.Stop(color: Color.black.opacity(0.55), location: 0),
                    Gradient.Stop(color: Color.black.opacity(0), location: 0.22),
                    Gradient.Stop(color: Color.black.opacity(0), location: 0.48),
                    Gradient.Stop(color: Color.black.opacity(0.25), location: 0.62),
                    Gradient.Stop(color: Color.black.opacity(0.82), location: 1),
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(width: size.width, height: size.height)
        .opacity(mediaOpacity)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func startVideo() {
        guard let media = input.facts.day0, media.kind == .video, let url = media.fileURL else { return }
        holder.start(url: url, playing: !input.isReady)
    }

    private func loadPhoto() async {
        guard let media = input.facts.day0, media.kind == .photo, let url = media.fileURL else { return }
        let loaded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }.value
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.28)) { photo = loaded }
    }

    // MARK: Top: progress, "you, on day 0", sound

    @ViewBuilder
    private func topChrome(handover: Double) -> some View {
        let layout = input.layout
        let top = layout.safeArea.top
        // Never runs under the close button: 16 pt in, then 44 + 12 clear of the right edge.
        let barWidth = max(0, layout.size.width - 16 - 16 - 44 - 12)
        let fraction = min(input.t, PauseScript.wait) / PauseScript.wait
        let visible = 1 - handover

        ZStack(alignment: .topLeading) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                Capsule().fill(Color.white).frame(width: barWidth * CGFloat(fraction))
            }
            .frame(width: barWidth, height: 2)
            .offset(x: 16, y: top + 2)
            .opacity(visible)
            .accessibilityHidden(true)

            if let day0 = input.facts.day0 {
                HStack(spacing: 8) {
                    Text("you, on day 0 · " + day0.capturedAt.formatted(.dateTime.month(.abbreviated).day()).lowercased())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .lineLimit(1)
                    // The wave belongs to the video's sound; a photo has none, so it shows no wave.
                    if day0.kind == .video {
                        Day0PauseWave(t: input.t, live: !isMuted && !input.isReady, reduceMotion: input.reduceMotion)
                    }
                }
                .offset(x: 16, y: top + 2 + 2 + 12)
                .opacity(visible)
                .accessibilityHidden(true)

                if day0.kind == .video {
                    muteButton
                        .opacity(visible)
                        .allowsHitTesting(visible > 0.5)
                        .accessibilityHidden(visible < 0.5)
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }

    /// 32 pt round toggle under the host's close button (44 pt hit area, centred under it).
    private var muteButton: some View {
        let layout = input.layout
        let y = layout.safeArea.top + PauseLayout.topRowOffset + 44 + 10
        return Button {
            isMuted.toggle()
            holder.setMuted(isMuted)
        } label: {
            ZStack {
                Circle().fill(Color.white.opacity(0.18))
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 32, height: 32)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMuted ? "unmute your day 0 video" : "mute your day 0 video")
        .position(x: layout.size.width - 16 - 22, y: y + 22)
    }

    // MARK: Beats

    private func currentIndex(_ beats: [Day0PauseBeat]) -> Int {
        var cur = -1
        for (i, beat) in beats.enumerated() where input.t >= beat.start { cur = i }
        return cur
    }

    /// Soft at each beat start, light at each tick of the first beat. `cue` plays once per id.
    private func fireHaptics(_ beats: [Day0PauseBeat], _ cur: Int, hasMedia: Bool) {
        if hasMedia {
            // Lower-third: soft each time the line changes (the prototype's ltFrame), no ground ticks.
            var line = -1
            for (i, l) in input.script.lines.enumerated() where input.t >= l.start { line = i }
            if line >= 0 { input.haptics.cue("d0.lt.\(line)", .soft) }
            return
        }
        guard cur >= 0 else { return }
        input.haptics.cue("d0.beat.\(cur)", .soft)
        let beat = beats[cur]
        if beat.kind == .ground {
            let lt = input.t - beat.start
            if lt >= 0.45 { input.haptics.cue("d0.tick.0", .light) }
            if lt >= 1.3 { input.haptics.cue("d0.tick.1", .light) }
        }
    }

    /// The over-the-video layer: one short line low on the screen plus chips, inside the safe zones
    /// (above the host's buttons, `Theme.pageMargin` from the sides).
    private func lowerThirdLayer() -> some View {
        let layout = input.layout
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            Day0PauseLowerThird(
                facts: input.facts,
                lines: input.script.lines,
                t: input.t,
                width: layout.contentWidth,
                compact: layout.size.height <= 700,
                reduceMotion: input.reduceMotion
            )
            .padding(.bottom, max(0, layout.size.height - layout.contentBottom))
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .bottom)
        .allowsHitTesting(false)
    }

    private func beatsLayer(beats: [Day0PauseBeat], cur: Int, k: CGFloat) -> some View {
        let layout = input.layout
        var shown: [Int] = []
        if cur >= 1, input.t - beats[cur].start < 0.24 { shown.append(cur - 1) }
        shown.append(cur)
        return ZStack {
            ForEach(shown, id: \.self) { i in
                beatView(beats: beats, index: i, cur: cur, k: k)
            }
        }
        .frame(width: layout.contentWidth, height: layout.contentHeight)
        .position(x: layout.size.width / 2, y: layout.contentTop + layout.contentHeight / 2)
        .allowsHitTesting(false)
    }

    /// Incoming: rises 10 pt and fades in over 360 ms. Outgoing: scales to 0.96 and fades over 240 ms.
    private func beatView(beats: [Day0PauseBeat], index i: Int, cur: Int, k: CGFloat) -> some View {
        let beat = beats[i]
        let reduce = input.reduceMotion
        var lt = input.t - beat.start
        var opacity = 1.0
        var scale = 1.0
        var rise = 0.0
        if i == cur {
            let p = day0Ease(day0Prog(lt, 0, 0.36))
            opacity = p
            rise = reduce ? 0 : 10 * (1 - p)
        } else {
            let next = beats[i + 1].start
            let po = day0Prog(input.t, next, 0.24)
            opacity = 1 - po
            scale = reduce ? 1 : 1 - 0.04 * po
            lt = next - beat.start
        }
        return beatContent(beat, lt: lt, k: k)
            .frame(width: input.layout.contentWidth)
            .scaleEffect(CGFloat(scale))
            .offset(y: CGFloat(rise))
            .opacity(opacity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label(for: beat))
            .accessibilityHidden(i != cur)
    }

    @ViewBuilder
    private func beatContent(_ beat: Day0PauseBeat, lt: Double, k: CGFloat) -> some View {
        let width = input.layout.contentWidth
        let reduce = input.reduceMotion
        switch beat.kind {
        case .ground:
            Day0PauseGroundBeat(facts: input.facts, lt: lt, k: k, width: width, reduceMotion: reduce)
        case .own:
            Day0PauseOwnBeat(quote: input.script.quote ?? beat.line?.text ?? "", lt: lt, k: k, reduceMotion: reduce)
        case .stake:
            Day0PauseStakeBeat(facts: input.facts, lt: lt, k: k, width: width, reduceMotion: reduce)
        case .fact:
            Day0PauseFactBeat(facts: input.facts, source: beat.line?.source, lt: lt, k: k, reduceMotion: reduce)
        case .close:
            Day0PauseCloseBeat(facts: input.facts, lt: lt, k: k)
        }
    }

    /// VoiceOver reads the line's full text (their own words beat reads the lead-in, quote and follow-up).
    private func label(for beat: Day0PauseBeat) -> String {
        switch beat.kind {
        case .own:
            return input.script.lines
                .filter { $0.kind == .own || $0.kind == .quote }
                .map(\.text)
                .joined(separator: " ")
        case .stake:
            let base = beat.line?.text ?? input.facts.d0StakeCaption
            let f = input.facts
            if f.streakWeeks > 0 {
                return base + " \(f.streakWeeks) \(f.streakWeeks == 1 ? "week" : "weeks") streak."
            }
            return base
        default:
            return beat.line?.text ?? ""
        }
    }

    // MARK: Doors

    private func doorsLayer(choice: PauseChoice, index: Int, age: Double, from: Int?, k: CGFloat) -> some View {
        let layout = input.layout
        let p = day0Ease(day0Prog(age, 0, 0.42))
        let reduce = input.reduceMotion
        let previous: PauseChoice? = {
            guard let from, from != index, age < 0.45, from >= 0, from < input.script.choices.count else { return nil }
            return input.script.choices[from]
        }()
        return ZStack {
            if let previous {
                Day0PauseDoor(choice: previous, facts: input.facts, age: 10, k: k, width: layout.contentWidth, reduceMotion: reduce)
                    .id(previous.key)
                    .offset(y: reduce ? 0 : CGFloat(-24 * p))
                    .opacity(1 - p)
                    .accessibilityHidden(true)
            }
            Day0PauseDoor(choice: choice, facts: input.facts, age: age, k: k, width: layout.contentWidth, reduceMotion: reduce)
                .id(choice.key)
                .offset(y: reduce ? 0 : CGFloat(24 * (1 - p)))
                .opacity(p)
        }
        .frame(width: layout.contentWidth, height: layout.contentHeight)
        .position(x: layout.size.width / 2, y: layout.contentTop + layout.contentHeight / 2)
        .allowsHitTesting(false)
    }
}

// MARK: - Over the video: the lower-third caption, chips and sound wave

/// The small audio wave after the "you, on day 0" label. Lit and moving while sound is on, dim and flat
/// while muted (the prototype's #wave). A photo has no sound, so the stage does not draw it there.
private struct Day0PauseWave: View {
    let t: Double
    let live: Bool
    let reduceMotion: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                let phase = Double(i)
                let moving = live && !reduceMotion
                let h: Double = moving ? 3 + 8 * abs(sin(t * (5 + phase * 1.7) + phase)) : 3
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 2, height: CGFloat(h))
            }
        }
        .frame(height: 11, alignment: .bottom)
        .opacity(live ? 1 : 0.35)
    }
}

/// One chip's real values. `bar` is the share of the 66 done, only on the visits chip.
private struct Day0PauseChipSpec: Identifiable {
    let key: String
    let value: String
    let unit: String
    var flame: Bool = false
    var bar: Double? = nil
    var id: String { key }
}

/// "6:58 AM" or "18:58" to minutes since midnight; nil when the label cannot be read (the chip then hides).
private func day0ClockMinutes(_ label: String) -> Int? {
    let lower = label.lowercased()
    let tokens = lower.split(whereSeparator: { !($0.isNumber || $0 == ":") })
    guard let token = tokens.first(where: { $0.contains(":") }) else { return nil }
    let parts = token.split(separator: ":")
    guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
    var h = hour
    let pm = lower.contains("pm") || lower.contains("p.m")
    let am = lower.contains("am") || lower.contains("a.m")
    if pm && h < 12 { h += 12 }
    if am && h == 12 { h = 0 }
    guard h >= 0, h < 24, minute >= 0, minute < 60 else { return nil }
    return h * 60 + minute
}

/// Port of the prototype's #lt: the current line as a lower-third caption (their own words in serif
/// italic with a "you, on day 0" kicker), and under it chips for the streak, the minutes to the gym
/// and the visit out of 66. The chip that matches the line on screen lifts.
private struct Day0PauseLowerThird: View {
    let facts: PauseFacts
    let lines: [PauseLine]
    let t: Double
    let width: CGFloat
    let compact: Bool
    let reduceMotion: Bool

    private static let flameGradient = LinearGradient(
        colors: [
            Color(red: 0.847, green: 0.153, blue: 0.075),
            Color(red: 1, green: 0.451, blue: 0),
            Color(red: 1, green: 0.769, blue: 0.180),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        let cur = currentIndex
        let spec = chipSpecs
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            captionArea(cur: cur)
            if !spec.isEmpty {
                chipsFitting(spec)
            }
        }
        .frame(width: width, alignment: .leading)
    }

    // MARK: Caption

    private var currentIndex: Int {
        var cur = -1
        for (i, line) in lines.enumerated() where t >= line.start { cur = i }
        return cur
    }

    private func captionArea(cur: Int) -> some View {
        var shown: [Int] = []
        if cur >= 1, t - lines[cur].start < 0.22 { shown.append(cur - 1) }
        if cur >= 0 { shown.append(cur) }
        return Color.clear
            .frame(width: width, height: 62)
            .overlay(alignment: .bottomLeading) {
                ZStack(alignment: .bottomLeading) {
                    ForEach(shown, id: \.self) { i in
                        captionLine(index: i, cur: cur)
                    }
                }
            }
    }

    /// Incoming: words fade in one after another. Outgoing: fades and lifts 8 pt over 220 ms.
    private func captionLine(index i: Int, cur: Int) -> some View {
        let line = lines[i]
        let isQuote = line.kind == .quote
        let raw = isQuote ? line.text.trimmingCharacters(in: CharacterSet(charactersIn: "\"\u{201C}\u{201D}")) : line.text
        let words = raw.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        let incoming = i == cur
        let po = incoming ? 0.0 : day0Prog(t, lines[min(cur, lines.count - 1)].start, 0.22)
        let size: CGFloat = compact ? (isQuote ? 22 : 20) : (isQuote ? 25 : 23)
        let n = words.count
        let stag: Double = n > 1 ? min(0.12, max(0, 0.35 * line.duration - 0.2) / Double(n - 1)) : 0
        let lt = t - line.start

        var out = AttributedString()
        for (j, word) in words.enumerated() {
            var piece = AttributedString(word)
            let a = incoming ? day0Prog(lt, Double(j) * stag, 0.22) : 1.0
            piece.foregroundColor = Color.white.opacity(a)
            out += piece
            if j < n - 1 { out += AttributedString(" ") }
        }

        let text: Text = isQuote
            ? Text(out).font(.system(size: size, weight: .medium, design: .serif).italic()).tracking(-0.01 * size)
            : Text(out).font(.system(size: size, weight: .bold)).tracking(-0.01 * size)

        return VStack(alignment: .leading, spacing: 0) {
            if isQuote {
                Text("you, on day 0")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.24)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
                    .opacity(incoming ? day0Prog(lt, 0, 0.3) : 1)
                    .padding(.bottom, 6)
            }
            text
                .lineSpacing(1)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
                .minimumScaleFactor(0.7)
                .shadow(color: Color.black.opacity(0.55), radius: 7, y: 1)
        }
        .frame(width: min(330, width), alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .opacity(1 - po)
        .offset(y: reduceMotion ? 0 : CGFloat(-8 * po))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.text)
        .accessibilityHidden(!incoming)
    }

    // MARK: Chips

    /// Only real values; one that is missing is left out.
    private var chipSpecs: [Day0PauseChipSpec] {
        var out: [Day0PauseChipSpec] = []
        if facts.streakWeeks > 0 {
            out.append(Day0PauseChipSpec(key: "stake", value: "\(facts.streakWeeks)", unit: facts.streakWeeks == 1 ? "week" : "weeks", flame: true))
        }
        if facts.context == .windowClosed {
            if facts.graceMinutes > 0 {
                out.append(Day0PauseChipSpec(key: "close", value: "+\(facts.graceMinutes)", unit: "min if you go now"))
            }
        } else if let by = facts.gymBy, let b = day0ClockMinutes(by), let n = day0ClockMinutes(facts.nowLabel) {
            out.append(Day0PauseChipSpec(key: "close", value: "\(max(0, b - n))", unit: "min to gym"))
        }
        let number = min(66, max(1, facts.visitNumber))
        let share = min(1.0, max(0.0, Double(facts.visitsBefore) / 66.0))
        out.append(Day0PauseChipSpec(key: "fact", value: "\(number)", unit: "of 66", bar: share))
        return out
    }

    /// Which chip the line on screen belongs to, and how far its lift has come (0...1, 0.35 s each way).
    private func onAmount(_ key: String) -> Double {
        var best = 0.0
        for (i, line) in lines.enumerated() {
            let mapped: String?
            switch line.kind {
            case .stake: mapped = "stake"
            case .fact: mapped = "fact"
            case .close, .ground: mapped = "close"
            case .own, .quote: mapped = nil
            }
            guard mapped == key, t >= line.start else { continue }
            let end: Double? = i + 1 < lines.count ? lines[i + 1].start : nil
            if let end, t >= end {
                best = max(best, 1 - day0Prog(t, end, 0.35))
            } else {
                best = max(best, day0Prog(t, line.start, 0.35))
            }
        }
        return best
    }

    /// Fits on one row if it can, then without the bar and with tighter padding, then on two rows,
    /// and last of all shrinks the text, so nothing overflows at 375 wide.
    private func chipsFitting(_ spec: [Day0PauseChipSpec]) -> some View {
        ViewThatFits(in: .horizontal) {
            chipRows(spec, tight: false, shrink: false, wrap: false)
            chipRows(spec, tight: true, shrink: false, wrap: false)
            chipRows(spec, tight: true, shrink: false, wrap: true)
            chipRows(spec, tight: true, shrink: true, wrap: true)
        }
        .frame(maxWidth: width, alignment: .leading)
    }

    @ViewBuilder
    private func chipRows(_ spec: [Day0PauseChipSpec], tight: Bool, shrink: Bool, wrap: Bool) -> some View {
        if wrap && spec.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Array(spec.dropLast())) { chip in
                        chipView(chip, tight: tight, shrink: shrink)
                    }
                }
                HStack(spacing: 8) {
                    chipView(spec[spec.count - 1], tight: tight, shrink: shrink)
                }
            }
        } else {
            HStack(spacing: 8) {
                ForEach(spec) { chip in
                    chipView(chip, tight: tight, shrink: shrink)
                }
            }
        }
    }

    private func chipView(_ chip: Day0PauseChipSpec, tight: Bool, shrink: Bool) -> some View {
        let on = onAmount(chip.key)
        let height: CGFloat = compact ? 34 : 38
        let valueSize: CGFloat = compact ? 15 : 17
        let unitSize: CGFloat = tight ? 11 : 12
        let scaleFloor: CGFloat = shrink ? 0.7 : 1
        return HStack(spacing: tight ? 6 : 7) {
            if chip.flame {
                Image(systemName: "flame.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Self.flameGradient)
                    .frame(width: 15, height: 18)
            }
            Text(chip.value)
                .font(.system(size: valueSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(scaleFloor)
            Text(chip.unit)
                .font(.system(size: unitSize, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.65))
                .lineLimit(1)
                .minimumScaleFactor(scaleFloor)
            if let bar = chip.bar, !tight {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.22))
                    Capsule().fill(Color.white).frame(width: 34 * CGFloat(bar))
                }
                .frame(width: 34, height: 4)
            }
        }
        .padding(.leading, tight ? 9 : 10)
        .padding(.trailing, tight ? 10 : 12)
        .frame(height: height)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(Color(red: 20.0 / 255, green: 20.0 / 255, blue: 22.0 / 255).opacity(0.42))
                Capsule().fill(Color.white.opacity(0.2 * on))
            }
            .environment(\.colorScheme, .dark)
        }
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.14 + 0.26 * on), lineWidth: 1)
        }
        .scaleEffect(reduceMotion ? 1 : CGFloat(1 + 0.04 * on))
        .offset(y: reduceMotion ? 0 : CGFloat(-3 * on))
    }
}

// MARK: - Beat list (the prototype's beat builder)

private struct Day0PauseBeat {
    enum Kind { case ground, own, stake, fact, close }

    let kind: Kind
    var start: Double
    let line: PauseLine?

    /// Port of mkBeats: ground, own words, stake, fact, close. The stake beat is always shown, even when
    /// its line was dropped to fit 30 s; then it starts at least 4.5 s after the quote (3.2 s after any
    /// other beat) and the next beat gives way, taking its time from the end of the stake.
    static func build(script: PauseScript) -> [Day0PauseBeat] {
        let lines = script.lines
        let ground = lines.first { $0.kind == .ground }
        let quote = lines.first { $0.kind == .quote }
        let stake = lines.first { $0.kind == .stake }
        let fact = lines.first { $0.kind == .fact }
        let close = lines.first { $0.kind == .close }

        var result: [Day0PauseBeat] = []
        if let ground { result.append(Day0PauseBeat(kind: .ground, start: ground.start, line: ground)) }
        if let quote { result.append(Day0PauseBeat(kind: .own, start: quote.start, line: quote)) }

        var factBeat: Day0PauseBeat? = fact.map { Day0PauseBeat(kind: .fact, start: $0.start, line: $0) }
        var closeBeat: Day0PauseBeat? = close.map { Day0PauseBeat(kind: .close, start: $0.start, line: $0) }
        let next: Day0PauseBeat? = factBeat ?? closeBeat

        let stakeStart: Double
        if let stake {
            stakeStart = stake.start
        } else {
            var need = 0.0
            if let prev = result.last { need = prev.kind == .own ? 4.5 : 3.2 }
            let prevStart = result.last?.start ?? 0
            let nextStart = next?.start ?? (PauseScript.wait - 3)
            stakeStart = max(prevStart + need, nextStart - 4)
        }
        result.append(Day0PauseBeat(kind: .stake, start: stakeStart, line: stake))

        if factBeat != nil {
            if factBeat!.start < stakeStart + 3.2 { factBeat!.start = stakeStart + 3.2 }
        } else if closeBeat != nil {
            if closeBeat!.start < stakeStart + 3.2 { closeBeat!.start = stakeStart + 3.2 }
        }
        if let fb = factBeat, closeBeat != nil, closeBeat!.start < fb.start + 2.5 {
            closeBeat!.start = fb.start + 2.5
        }
        if let factBeat { result.append(factBeat) }
        if let closeBeat { result.append(closeBeat) }

        return result.sorted { $0.start < $1.start }
    }
}

private extension PauseFacts {
    /// The stake beat's caption (the prototype's).
    var d0StakeCaption: String {
        if lastSkipped { return "two skips in a row cools it." }
        if weekAtRisk { return "skip and the week is out." }
        return "today keeps the flame."
    }
}

// MARK: - Shared drawing bits

private struct Day0PauseCaption: View {
    let text: String
    let opacity: Double
    let k: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: 20 * max(k, 0.9), weight: .semibold))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: 300)
            .shadow(color: Color.black.opacity(0.5), radius: 5, y: 1)
            .opacity(opacity)
    }
}

private struct Day0PauseHLine: Shape {
    let x0: CGFloat
    let x1: CGFloat
    let y: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x0, y: y))
        p.addLine(to: CGPoint(x: x1, y: y))
        return p
    }
}

private struct Day0PauseCheck: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 22
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.move(to: CGPoint(x: c.x - 5 * s, y: c.y + 0.5 * s))
        p.addLine(to: CGPoint(x: c.x - 1.5 * s, y: c.y + 4 * s))
        p.addLine(to: CGPoint(x: c.x + 5.5 * s, y: c.y - 3.5 * s))
        return p
    }
}

/// The home page's week row (MomentumFlameProgress), drawn for this dark surface: the same SF
/// flame, the same lit gradient (Theme.accentWarm, accent, accentDeep), the same coral underline and
/// connector, the same sizing rule. Only the unlit greys are lifted, because Home's 30% grey on its
/// light canvas would vanish on near-black. It is drawn here rather than reused because the Home view
/// plays its own tap when a flame lights, which would double the pause's haptics.
private struct Day0PauseFlameRow: View {
    let counted: Int
    let goal: Int
    let width: CGFloat
    /// The flame that lights on this screen (today's), if any; it lights over 0.25 s.
    var lightingIndex: Int? = nil
    var lightProgress: Double = 0
    var reduceMotion: Bool = false

    var body: some View {
        if goal > 0 {
            let n = CGFloat(goal)
            let gaps = n - 1
            let flame: CGFloat = {
                var f = width / (n + gaps * 0.6)
                f = min(max(f, 14), 40)
                if gaps > 0 { f = min(f, (width - gaps * 10) / n) }
                return max(f, 10)
            }()
            let connector: CGFloat = gaps > 0 ? min(max((width - n * flame) / gaps, 10), 40) : 0
            HStack(spacing: 0) {
                ForEach(0..<goal, id: \.self) { i in
                    if i > 0 {
                        connectorView(filled: litAmount(i - 1) >= 1 && litAmount(i) > 0)
                            .frame(width: connector)
                            .offset(y: flame * 0.1)
                    }
                    flameView(lit: litAmount(i), isNext: i == counted && lightingIndex == nil, size: flame)
                }
            }
            .frame(width: width)
            .padding(.bottom, 10)
            .accessibilityHidden(true)
        }
    }

    /// 0 unlit, 1 lit; the lighting flame in between.
    private func litAmount(_ i: Int) -> Double {
        if i < counted { return 1 }
        if let lightingIndex, i == lightingIndex { return min(1, max(0, lightProgress)) }
        return 0
    }

    private func flameView(lit: Double, isNext: Bool, size: CGFloat) -> some View {
        ZStack {
            Image(systemName: "flame.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.white.opacity(isNext ? 0.42 : 0.3))
                .opacity(1 - lit)
            Image(systemName: "flame.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(LinearGradient(colors: [Theme.accentWarm, Theme.accent, Theme.accentDeep], startPoint: .top, endPoint: .bottom))
                .opacity(lit)
                .scaleEffect(reduceMotion ? 1 : CGFloat(0.9 + 0.1 * lit))
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottom) {
            ZStack {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(Theme.accent).opacity(lit)
            }
            .frame(width: size * 0.72, height: 3)
            .offset(y: 8)
        }
    }

    private func connectorView(filled: Bool) -> some View {
        ZStack {
            Day0PauseDash()
                .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.5, 4]))
                .opacity(filled ? 0 : 1)
            Capsule().fill(Theme.accent).opacity(filled ? 1 : 0)
        }
        .frame(height: 2)
        .padding(.horizontal, 3)
    }
}

private struct Day0PauseDash: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

// MARK: - Beat 1: ground

private struct Day0PauseGroundBeat: View {
    let facts: PauseFacts
    let lt: Double
    let k: CGFloat
    let width: CGFloat
    let reduceMotion: Bool

    var body: some View {
        let r = 36 * k
        let w = min(334, width)
        let cx0 = r
        let cx1 = w / 2
        let cx2 = w - r
        let a2 = cx1 + r
        let b2 = cx2 - r
        let x2 = a2 + (b2 - a2) * 0.5
        let h = r * 2 + 34 * k
        let closed = facts.context == .windowClosed

        let s1 = day0Ease(day0Prog(lt, 0.85, 0.4))
        let s2 = day0Ease(day0Prog(lt, 1.8, 0.8))
        let dotP = day0Prog(lt, 2.5, 0.2)
        let pz = (reduceMotion || lt < 2.5) ? 0.0 : ((lt - 2.5).truncatingRemainder(dividingBy: 1.4)) / 1.4

        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                // The road ahead, dotted.
                Day0PauseHLine(x0: a2, x1: b2, y: r)
                    .stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 5]))
                // Drawn: alarm to up, then up toward the gym, stopping at the dot.
                Day0PauseHLine(x0: cx0 + r, x1: cx1 - r, y: r)
                    .trim(from: 0, to: CGFloat(s1))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .opacity(s1 > 0 ? 1 : 0)
                Day0PauseHLine(x0: a2, x1: x2, y: r)
                    .trim(from: 0, to: CGFloat(s2))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .opacity(s2 > 0 ? 1 : 0)

                Circle()
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: CGFloat(2 * (5 + 8 * pz)), height: CGFloat(2 * (5 + 8 * pz)))
                    .opacity(dotP * (1 - pz) * 0.6)
                    .position(x: x2, y: r)
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .opacity(dotP)
                    .position(x: x2, y: r)

                node(cx: cx0, symbol: "bell.fill", on: true, r: r)
                node(cx: cx1, symbol: "sunrise.fill", on: true, r: r)
                node(cx: cx2, symbol: "dumbbell.fill", on: false, r: r)

                tick(cx: cx0, at: 0.45, r: r)
                tick(cx: cx1, at: 1.3, r: r)

                if let alarm = facts.alarmLabel {
                    nodeLabel(alarm, cx: cx0, w: w, r: r, strong: false)
                }
                nodeLabel("up", cx: cx1, w: w, r: r, strong: false)
                if let gym = gymLabel(closed: closed) {
                    nodeLabel(gym, cx: cx2, w: w, r: r, strong: closed)
                }
            }
            .frame(width: w, height: h, alignment: .topLeading)

            Day0PauseCaption(text: "two of three done.", opacity: day0Prog(lt, 1.9, 0.4), k: k)
                .padding(.top, 28 * k)
        }
    }

    private func gymLabel(closed: Bool) -> String? {
        if closed {
            if let by = facts.gymBy { return by + " · " + facts.nowLabel + " now" }
            return facts.nowLabel + " now"
        }
        if let by = facts.gymBy { return "gym by " + by }
        return nil
    }

    private func node(cx: CGFloat, symbol: String, on: Bool, r: CGFloat) -> some View {
        Circle()
            .strokeBorder(Color.white.opacity(on ? 0.9 : 0.3), lineWidth: 2)
            .frame(width: 2 * r, height: 2 * r)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 30 * k, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(on ? 1 : 0.6))
            }
            .position(x: cx, y: r)
    }

    /// Labels may be wider than their node; they are kept within 24 pt of the row so the page margin holds.
    private func nodeLabel(_ text: String, cx: CGFloat, w: CGFloat, r: CGFloat, strong: Bool) -> some View {
        let labelWidth: CGFloat = 120
        let centre = min(max(cx, labelWidth / 2 - 24), w + 24 - labelWidth / 2)
        return Text(text)
            .font(.system(size: 14, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Color.white.opacity(strong ? 1 : 0.6))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: labelWidth)
            .position(x: centre, y: 2 * r + 16 * k)
    }

    private func tick(cx: CGFloat, at: Double, r: CGFloat) -> some View {
        let p = day0Prog(lt, at, 0.25)
        let scale = reduceMotion ? 1.0 : 0.6 + 0.4 * day0Ease(p)
        return ZStack {
            Circle().fill(Color.white)
            Day0PauseCheck()
                .trim(from: 0, to: CGFloat(day0Prog(lt, at + 0.15, 0.3)))
                .stroke(Color(red: 0.043, green: 0.043, blue: 0.047), style: StrokeStyle(lineWidth: 2.4 * k, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 22 * k, height: 22 * k)
        .scaleEffect(CGFloat(scale))
        .opacity(p > 0 ? 1 : 0)
        .position(x: cx + 25 * k, y: r - 25 * k)
    }
}

// MARK: - Beat 2: their own words

private struct Day0PauseOwnBeat: View {
    let quote: String
    let lt: Double
    let k: CGFloat
    let reduceMotion: Bool

    var body: some View {
        let words = quote
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"\u{201C}\u{201D}"))
            .split(separator: " ")
            .map(String.init)
        let markIn = day0Prog(lt, 0.1, 0.5)
        let closeAt = 0.45 + Double(words.count) * 0.14

        VStack(spacing: 0) {
            Text("you, on day 0")
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Color.white.opacity(0.55))
                .opacity(day0Prog(lt, 0.1, 0.4))
                .padding(.bottom, 6)

            Text("\u{201C}")
                .font(.system(size: 96 * k, design: .serif))
                .foregroundStyle(Color.white.opacity(0.28))
                .frame(height: 56 * k, alignment: .top)
                .scaleEffect(reduceMotion ? 1 : CGFloat(0.85 + 0.15 * day0Ease(markIn)))
                .opacity(markIn)

            quoteText(words)
                .font(.system(size: 30 * k, weight: .medium, design: .serif).italic())
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .lineLimit(5)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 310)
                .padding(.top, 6)

            Text("\u{201D}")
                .font(.system(size: 96 * k, design: .serif))
                .foregroundStyle(Color.white.opacity(0.28))
                .frame(height: 30 * k, alignment: .top)
                .padding(.top, 2)
                .opacity(day0Prog(lt, closeAt, 0.4))
        }
        .shadow(color: Color.black.opacity(0.4), radius: 6, y: 1)
    }

    /// Word by word: each word fades in 140 ms after the one before.
    private func quoteText(_ words: [String]) -> Text {
        var out = AttributedString()
        for (i, word) in words.enumerated() {
            var piece = AttributedString(word)
            piece.foregroundColor = Color.white.opacity(day0Prog(lt, 0.45 + Double(i) * 0.14, 0.3))
            out += piece
            if i < words.count - 1 { out += AttributedString(" ") }
        }
        return Text(out)
    }
}

// MARK: - Beat 3: what is on the line (the real flames)

private struct Day0PauseStakeBeat: View {
    let facts: PauseFacts
    let lt: Double
    let k: CGFloat
    let width: CGFloat
    let reduceMotion: Bool

    /// Same colours as StreakChip's flame.
    private static let flameOrange = Color(red: 1, green: 0.451, blue: 0)
    private static let flameGradient = LinearGradient(
        colors: [
            Color(red: 0.847, green: 0.153, blue: 0.075),
            Color(red: 1, green: 0.451, blue: 0),
            Color(red: 1, green: 0.769, blue: 0.180),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        // The big flame weakens for about a second, then recovers.
        let weak = facts.lastSkipped || facts.weekAtRisk
        let w: Double = weak
            ? (reduceMotion ? 0.7 : day0Prog(lt, 0.5, 0.4) * (1 - day0Prog(lt, 1.8, 0.7)))
            : 0

        VStack(spacing: 0) {
            if facts.streakWeeks > 0 {
                HStack(spacing: 14 * k) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 92 * k, weight: .regular))
                        .foregroundStyle(Self.flameGradient)
                        .shadow(color: Self.flameOrange.opacity(0.45), radius: 12 * k, y: 4 * k)
                        .saturation(1 - 0.4 * w)
                        .scaleEffect(CGFloat(1 - 0.08 * w))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(facts.streakWeeks)")
                            .font(.system(size: 88 * k, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(facts.streakWeeks == 1 ? "week" : "weeks")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                }
                .padding(.bottom, 30 * k)
            }

            Day0PauseFlameRow(counted: facts.weekDone, goal: facts.weekGoal, width: min(width, 320))

            Day0PauseCaption(text: facts.d0StakeCaption, opacity: day0Prog(lt, 0.9, 0.4), k: k)
                .padding(.top, 28 * k)
        }
    }
}

// MARK: - Beat 4: the 66 visits

private struct Day0PauseFactBeat: View {
    let facts: PauseFacts
    let source: String?
    let lt: Double
    let k: CGFloat
    let reduceMotion: Bool

    var body: some View {
        let v = facts.visitsBefore
        let stage = PauseScript.stage(visitsBefore: v)
        let isHabit = stage == .habit
        let caption: String = {
            switch stage {
            case .new: return "the first minutes are the worst."
            case .building: return "each visit gets easier."
            case .close: return "\(66 - v) more and it's automatic."
            case .habit: return "one more keeps it automatic."
            }
        }()
        let src = source ?? (stage == .new ? "ruby et al., 2011" : "lally et al., 2010")
        let d = 10 * k
        let gap = 9 * k
        let cols = 11
        let rows = 6
        let gridW = CGFloat(cols) * d + CGFloat(cols - 1) * gap
        let gridH = CGFloat(rows) * d + CGFloat(rows - 1) * gap
        let step = min(0.03, 1.1 / Double(max(1, v)))
        let nextP = day0Prog(lt, 0.3 + Double(v) * step + 0.2, 0.3)
        let pulse = reduceMotion ? 0.0 : sin(Double.pi * day0Prog(lt, 1.7, 0.9))

        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(isHabit ? v : facts.visitNumber)")
                    .font(.system(size: 76 * k, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(isHabit ? "visits" : "of 66")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .padding(.bottom, 18 * k)

            Canvas { context, _ in
                for i in 0..<(cols * rows) {
                    let col = i % cols
                    let row = i / cols
                    let x = CGFloat(col) * (d + gap)
                    let y = CGFloat(row) * (d + gap)
                    let rect = CGRect(x: x, y: y, width: d, height: d)
                    if i < min(v, 66) {
                        let p = day0Prog(lt, 0.3 + Double(i) * step, 0.2)
                        context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.16 + 0.84 * p)))
                    } else if i == v && v < 66 {
                        // The next one: hollow, pulsing once.
                        context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.16 * (1 - nextP))))
                        let grow = CGFloat(1 + 0.55 * pulse)
                        let side = d * grow
                        let ring = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
                        context.stroke(Path(ellipseIn: ring.insetBy(dx: 1, dy: 1)), with: .color(Color.white.opacity(nextP)), lineWidth: 2)
                    } else {
                        context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.16)))
                    }
                }
            }
            .frame(width: gridW, height: gridH)
            .accessibilityHidden(true)

            Day0PauseCaption(text: caption, opacity: day0Prog(lt, 1.0, 0.4), k: k)
                .padding(.top, 28 * k)

            Text(src)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .opacity(day0Prog(lt, 1.5, 0.4))
                .padding(.top, 8)
        }
    }
}

// MARK: - Beat 5: the way forward

private struct Day0PauseCloseBeat: View {
    let facts: PauseFacts
    let lt: Double
    let k: CGFloat

    var body: some View {
        let closed = facts.context == .windowClosed

        VStack(spacing: 0) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 46 * k, weight: .semibold))
                .foregroundStyle(Color.white)
                .opacity(day0Prog(lt, 0, 0.4))

            if closed {
                Text("+\(facts.graceMinutes)")
                    .font(.system(size: 72 * k, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.top, 14)
                    .opacity(day0Prog(lt, 0.2, 0.4))
                Text("min")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.top, 12)
                    .opacity(day0Prog(lt, 0.4, 0.4))
            } else if let by = facts.gymBy {
                Text("gym by")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.top, 20)
                    .opacity(day0Prog(lt, 0.2, 0.4))
                Text(by)
                    .font(.system(size: 72 * k, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.top, 6)
                    .opacity(day0Prog(lt, 0.4, 0.4))
            }

            Day0PauseCaption(
                text: closed ? "if you go now." : "you can still make it.",
                opacity: day0Prog(lt, 0.9, 0.4),
                k: k
            )
            .padding(.top, 28 * k)
        }
    }
}

// MARK: - The doors

private struct Day0PauseDoor: View {
    let choice: PauseChoice
    let facts: PauseFacts
    let age: Double
    let k: CGFloat
    let width: CGFloat
    let reduceMotion: Bool

    var body: some View {
        let titleSize = 34 * max(k, 0.88)
        let perks = visiblePerks()

        VStack(spacing: 0) {
            visual
                .padding(.bottom, 22 * k)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                Text(choice.title)
                    .font(.system(size: titleSize, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text(choice.lead)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 10)

                if !perks.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(Array(perks.enumerated()), id: \.offset) { index, perk in
                            let p = day0Prog(age, 0.2 + Double(index) * 0.06, 0.3)
                            Text(perk)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .opacity(p)
                                .offset(y: reduceMotion ? 0 : CGFloat(8 * (1 - p)))
                        }
                    }
                    .padding(.top, 14)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .frame(width: width)
    }

    /// At most two perks, the prototype's picks (home swaps its third for the month's pips).
    private func visiblePerks() -> [String] {
        let keep: [Int]
        switch choice.key {
        case .gym: keep = [0, 2]
        case .home: keep = [1]
        case .cant: keep = [0, 1]
        }
        return keep.compactMap { $0 < choice.perks.count ? choice.perks[$0] : nil }
    }

    @ViewBuilder
    private var visual: some View {
        switch choice.key {
        case .gym:
            VStack(spacing: 14 * k) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 52 * k, weight: .semibold))
                    .foregroundStyle(Color.white)
                // Today's flame lights once the door has been there a moment.
                Day0PauseFlameRow(counted: facts.weekDone, goal: facts.weekGoal, width: min(width, 320), lightingIndex: facts.weekDone < facts.weekGoal ? facts.weekDone : nil, lightProgress: (age - 0.3) / 0.25, reduceMotion: reduceMotion)
            }
        case .home:
            VStack(spacing: 14 * k) {
                Image(systemName: "house.fill")
                    .font(.system(size: 52 * k, weight: .semibold))
                    .foregroundStyle(Color.white)
                Day0PauseFlameRow(counted: facts.weekDone, goal: facts.weekGoal, width: min(width, 320), lightingIndex: facts.weekDone < facts.weekGoal ? facts.weekDone : nil, lightProgress: (age - 0.3) / 0.25, reduceMotion: reduceMotion)
                homePips
            }
        case .cant:
            VStack(spacing: 14 * k) {
                Day0PauseCalendar(week: facts.week, age: age, width: width, k: k, reduceMotion: reduceMotion)
                // Not lit: skipping today does not light today's flame.
                Day0PauseFlameRow(counted: facts.weekDone, goal: facts.weekGoal, width: min(width, 320))
            }
        }
    }

    private var homePips: some View {
        let limit = HomeWorkoutRules.monthlyLimit
        return HStack(spacing: 6) {
            ForEach(0..<limit, id: \.self) { i in
                Circle()
                    .strokeBorder(Color.white.opacity(i < facts.homeLeft ? 1 : 0.55), lineWidth: 1.5)
                    .background(Circle().fill(i < facts.homeLeft ? Color.white : Color.clear))
                    .frame(width: 10, height: 10)
            }
            Text("\(facts.homeLeft) of \(limit) left this month")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.leading, 6)
        }
    }
}

/// The week as a calendar card; today's mark slides to the next planned day, then fills.
private struct Day0PauseCalendar: View {
    let week: [PauseWeekDay]
    let age: Double
    let width: CGFloat
    let k: CGFloat
    let reduceMotion: Bool

    var body: some View {
        if week.isEmpty {
            EmptyView()
        } else {
            let cw = min(38, (width - 28) / CGFloat(max(week.count, 1)))
            let ti = week.firstIndex { $0.state == .today }
            let to: Int? = {
                guard let ti else { return nil }
                return week.indices.first { $0 > ti && week[$0].state == .planned }
            }()
            let markSize = 18 * k
            let move = reduceMotion ? 1.0 : day0Ease(day0Prog(age, 0.5, 0.7))
            let fill = reduceMotion ? day0Prog(age, 0.2, 0.2) : day0Prog(age, 1.15, 0.3)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        Text(day.letter)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .frame(width: cw)
                    }
                }
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        cell(day.state, size: markSize)
                            .frame(width: cw, height: 40 * k)
                    }
                }
                .overlay(alignment: .leading) {
                    if let ti {
                        let target = to ?? ti
                        let x = (CGFloat(ti) + CGFloat(move) * CGFloat(target - ti)) * cw + cw / 2 - markSize / 2
                        ZStack {
                            Circle().fill(Color.white.opacity(to == nil ? 0 : fill))
                            Circle().strokeBorder(Color.white, lineWidth: 2)
                        }
                        .frame(width: markSize, height: markSize)
                        .offset(x: x)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
            }
            .overlay(alignment: .topLeading) {
                Capsule().fill(Color.white.opacity(0.8)).frame(width: 2, height: 12).offset(x: 62, y: -8)
            }
            .overlay(alignment: .topTrailing) {
                Capsule().fill(Color.white.opacity(0.8)).frame(width: 2, height: 12).offset(x: -62, y: -8)
            }
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func cell(_ state: PauseWeekDay.State, size: CGFloat) -> some View {
        switch state {
        case .done:
            Circle().fill(Color.white).frame(width: size, height: size)
        case .planned:
            Circle()
                .strokeBorder(Color.white.opacity(0.65), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(width: size, height: size)
        case .today, .rest, .missed:
            Circle().fill(Color.white.opacity(0.2)).frame(width: 5, height: 5)
        }
    }
}

// MARK: - Video

/// Holds the looping player. Cheap to create (the host rebuilds the stage every frame); the player is
/// made once, in `start`, and released in `stop`.
@Observable
final class Day0PauseVideoHolder {
    var player: AVQueuePlayer?
    @ObservationIgnored private var looper: AVPlayerLooper?

    func start(url: URL, playing: Bool) {
        guard player == nil else { return }
        // Muted playback needs no audio session change, so the user's music and the app's own audio
        // setup are left exactly as they were until the toggle is pressed.
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
        player = queue
        if playing { queue.play() }
    }

    func pause() {
        player?.pause()
    }

    func setMuted(_ muted: Bool) {
        if !muted { takeSession() } else { restoreSession() }
        player?.isMuted = muted
    }

    func stop() {
        player?.pause()
        looper?.disableLooping()
        player?.removeAllItems()
        looper = nil
        player = nil
        restoreSession()
    }

    /// The category in place before the user unmuted, put back when they mute again or leave.
    @ObservationIgnored private var savedSession: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?

    private func takeSession() {
        let session = AVAudioSession.sharedInstance()
        if savedSession == nil { savedSession = (session.category, session.mode, session.categoryOptions) }
        // Unmuting plays alongside the user's music and is heard with the silent switch on.
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func restoreSession() {
        guard let saved = savedSession else { return }
        savedSession = nil
        try? AVAudioSession.sharedInstance().setCategory(saved.0, mode: saved.1, options: saved.2)
    }
}

private final class Day0PausePlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // layerClass guarantees the type.
        layer as! AVPlayerLayer
    }
}

private struct Day0PausePlayerView: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> Day0PausePlayerUIView {
        let view = Day0PausePlayerUIView()
        view.backgroundColor = .clear
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: Day0PausePlayerUIView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}
