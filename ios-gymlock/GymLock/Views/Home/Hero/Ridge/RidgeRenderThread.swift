//
//  RidgeRenderThread.swift
//  GymLock · Ridge hero card
//
//  The Ridge painting is CPU CoreGraphics: the first frame of a key paints every cached layer
//  (sky, mountains, mist, paper grain), and in an unoptimised build that can take long enough
//  to stall the main thread at launch. Frames are therefore painted here, on one dedicated
//  thread with a large stack, and handed back to the main thread when finished.
//
//  Jobs are coalesced per owner: while a frame is painting, only the newest request of each
//  card is kept, so a slow frame drops frames instead of queueing them.
//

import Foundation

nonisolated final class RidgeRenderThread: @unchecked Sendable {
    static let shared = RidgeRenderThread()

    private let cond = NSCondition()
    private var pending: [ObjectIdentifier: @Sendable () -> Void] = [:]
    private var order: [ObjectIdentifier] = []
    private var thread: Thread?

    private init() {}

    /// Replace `owner`'s waiting job (if any) with `job`.
    func submit(_ owner: AnyObject, _ job: @escaping @Sendable () -> Void) {
        let id = ObjectIdentifier(owner)
        cond.lock()
        if pending[id] == nil { order.append(id) }
        pending[id] = job
        if thread == nil { startLocked() }
        cond.signal()
        cond.unlock()
    }

    private func startLocked() {
        let t = Thread { [unowned self] in self.loop() }
        t.name = "GymLock.RidgeRender"
        t.stackSize = 16 << 20
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
        HeroTrace.log("ridge.thread start")
    }

    private func loop() {
        while true {
            cond.lock()
            while order.isEmpty { cond.wait() }
            let id = order.removeFirst()
            let job = pending.removeValue(forKey: id)
            cond.unlock()
            autoreleasepool { job?() }
        }
    }
}

/// Debug-only breadcrumbs for the hero card ("event key=value"), read with the runtime logs.
nonisolated enum HeroTrace {
    static func log(_ line: @autoclosure () -> String) {
        #if DEBUG
        print("[hero] \(line())")
        #endif
    }

    static func ms(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}
