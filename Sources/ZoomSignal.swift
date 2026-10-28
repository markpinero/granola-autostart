import Darwin
import Foundation

/// Active while Zoom's in-meeting helper runs (muted or not).
final class ZoomSignal: Signal {
    let name = "zoom"
    let processName: String
    init(processName: String = "CptHost") { self.processName = processName }

    func isActive(now: Date) -> Bool { Self.processRunning(processName) }

    static func processRunning(_ target: String) -> Bool {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return false }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var buf = [CChar](repeating: 0, count: 256)
        for pid in pids.prefix(Int(max(n, 0))) where pid > 0 {
            if proc_name(pid, &buf, UInt32(buf.count)) > 0, String(cString: buf) == target { return true }
        }
        return false
    }
}
