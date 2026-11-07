//
//  CrashSentinel.swift
//  GymLock
//
//  Temporary launch diagnostics. The preview has been exiting shortly after launch with no trace,
//  so this records what happened and shows it on the next launch:
//    - a crash signal (Swift traps, bad memory access, aborts): the signal, the stage the app had
//      reached, the crashing thread's stack, and the tail of stderr (where Swift prints
//      "Fatal error: ... file:line").
//    - a launch that never reached "launch.ok" without a signal: the process was killed from
//      outside (memory, watchdog, the preview host), with the last stage it reached.
//
//  Off in App Store builds. Remove once the launch crash is fixed.
//

import Foundation
import Darwin

private nonisolated(unsafe) var sentinelCrashPath: UnsafeMutablePointer<CChar>?
private nonisolated(unsafe) let sentinelStage = UnsafeMutablePointer<CChar>.allocate(capacity: 256)
private nonisolated(unsafe) let sentinelOld = UnsafeMutablePointer<sigaction>.allocate(capacity: 32)
private nonisolated(unsafe) let sentinelFrames = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 96)
private nonisolated(unsafe) let sentinelBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
private nonisolated(unsafe) var sentinelPipe: Int32 = -1

private nonisolated func sentinelWrite(_ fd: Int32, _ s: UnsafePointer<CChar>) {
    _ = write(fd, s, strlen(s))
}

private nonisolated func sentinelWriteInt(_ fd: Int32, _ v: Int32) {
    var n = v < 0 ? -Int(v) : Int(v)
    var digits: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    withUnsafeMutableBytes(of: &digits) { raw in
        var i = 11
        repeat {
            raw[i] = UInt8(48 + n % 10)
            n /= 10
            i -= 1
        } while n > 0 && i >= 0
        if v < 0, i >= 0 { raw[i] = 45; i -= 1 }
        _ = write(fd, raw.baseAddress! + i + 1, 11 - i)
    }
}

/// Runs on the crashing thread. Only async-signal-safe calls: open, write, read, backtrace.
private nonisolated func sentinelHandler(_ sig: Int32) {
    if let path = sentinelCrashPath {
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        if fd >= 0 {
            sentinelWrite(fd, "crash signal ")
            sentinelWriteInt(fd, sig)
            sentinelWrite(fd, "\nstage: ")
            sentinelWrite(fd, sentinelStage)
            sentinelWrite(fd, "\n\nstack:\n")
            let n = backtrace(sentinelFrames, 96)
            backtrace_symbols_fd(sentinelFrames, n, fd)
            if sentinelPipe >= 0 {
                sentinelWrite(fd, "\nstderr (unread):\n")
                var guardCount = 0
                while guardCount < 64 {
                    let r = read(sentinelPipe, sentinelBuf, 4096)
                    if r <= 0 { break }
                    _ = write(fd, sentinelBuf, r)
                    guardCount += 1
                }
            }
            close(fd)
        }
    }
    // Hand the signal back: the previous handler (or the default) runs when the faulting
    // instruction re-executes, or when abort() re-raises.
    _ = sigaction(sig, sentinelOld + Int(sig), nil)
}

nonisolated enum CrashSentinel {
    static let signals: [Int32] = [SIGTRAP, SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGFPE]

    static var isEnabled: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent != "receipt"
        #endif
    }

    private static let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CrashSentinel", isDirectory: true)
    private static var crashURL: URL { dir.appendingPathComponent("crash.txt") }
    private static var stageURL: URL { dir.appendingPathComponent("stage.txt") }
    private static var pendingURL: URL { dir.appendingPathComponent("pending") }
    private static var stderrURL: URL { dir.appendingPathComponent("stderr.log") }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var installed = false
    nonisolated(unsafe) private static var filedStages: Set<String> = []

    /// What went wrong on the previous launch, if it did not finish.
    nonisolated(unsafe) private(set) static var previousReport: String?
    /// Set from the report screen: the hero card skips its painting for this run.
    nonisolated(unsafe) static var heroSafeMode = false

    static func install() {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !installed else { return }
        installed = true
        sentinelStage.initialize(repeating: 0, count: 256)

        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        previousReport = readPrevious()
        try? fm.removeItem(at: crashURL)
        try? fm.removeItem(at: stderrURL)
        fm.createFile(atPath: pendingURL.path, contents: Data())

        sentinelCrashPath = strdup(crashURL.path)
        for s in signals {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = sentinelHandler
            action.sa_mask = 0
            action.sa_flags = 0
            _ = sigaction(s, &action, sentinelOld + Int(s))
        }
        teeStderr()
        markLocked("app.init")
    }

    /// The furthest point the app has reached. Cheap: the file is written once per distinct stage.
    static func mark(_ stage: String) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        markLocked(stage)
    }

    private static func markLocked(_ stage: String) {
        guard installed else { return }
        _ = stage.withCString { strncpy(sentinelStage, $0, 255) }
        let key = String(stage.prefix { $0 != " " })
        if !filedStages.contains(key) {
            filedStages.insert(key)
            try? stage.write(to: stageURL, atomically: false, encoding: .utf8)
        }
    }

    /// The launch got far enough: a later exit is no longer a launch failure.
    static func launchSucceeded() {
        guard isEnabled else { return }
        mark("launch.ok")
        try? FileManager.default.removeItem(at: pendingURL)
    }

    static func clearPrevious() {
        previousReport = nil
    }

    private static func readPrevious() -> String? {
        let fm = FileManager.default
        let crash = try? String(contentsOf: crashURL, encoding: .utf8)
        let pending = fm.fileExists(atPath: pendingURL.path)
        guard crash != nil || pending else { return nil }
        var out: [String] = []
        let stage = (try? String(contentsOf: stageURL, encoding: .utf8)) ?? "none"
        out.append("GymLock launch report")
        out.append("last stage written: \(stage)")
        if let crash {
            out.append("")
            out.append(crash)
        } else {
            out.append("no crash signal: the process was stopped from outside (memory, watchdog or the preview host)")
        }
        if let err = try? String(contentsOf: stderrURL, encoding: .utf8), !err.isEmpty {
            out.append("")
            out.append("stderr (last 6000 chars):")
            out.append(String(err.suffix(6000)))
        }
        return out.joined(separator: "\n")
    }

    /// Copies stderr into a file while still passing it through, so Swift's fatal error message
    /// survives the crash.
    private static func teeStderr() {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return }
        let original = dup(STDERR_FILENO)
        guard original >= 0 else { return }
        let logFD = open(stderrURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard dup2(fds[1], STDERR_FILENO) >= 0 else { return }
        setvbuf(stderr, nil, _IONBF, 0)
        let readFD = fds[0]
        _ = fcntl(readFD, F_SETFL, fcntl(readFD, F_GETFL) | O_NONBLOCK)
        sentinelPipe = readFD
        let t = Thread {
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            var p = pollfd(fd: readFD, events: Int16(POLLIN), revents: 0)
            while true {
                p.revents = 0
                if poll(&p, 1, -1) <= 0 { continue }
                while true {
                    let n = read(readFD, buf, 4096)
                    if n <= 0 { break }
                    _ = write(original, buf, n)
                    if logFD >= 0 { _ = write(logFD, buf, n) }
                }
            }
        }
        t.name = "GymLock.StderrTee"
        t.qualityOfService = .utility
        t.start()
    }
}
