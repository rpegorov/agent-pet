import Darwin
import Foundation

// Finds where an agent session is hosted by walking up the process tree.
public enum ProcessOrigin {
    public struct Result: Equatable, Sendable {
        public let app: String?
        public let tty: String?
    }

    private static let maxDepth = 16
    private static let appMarker = ".app/Contents/MacOS/"
    private static let appSuffix = ".app"
    private static let infoPlistPath = "Contents/Info.plist"
    private static let bundleIdentifierKey = "CFBundleIdentifier"
    private static let devicePrefix = "/dev/"
    private static let noDevice: Int32 = -1
    private static let deviceNameCapacity = 64

    public static func capture(from pid: pid_t = getpid()) -> Result {
        var tty: String?
        var topApp: String?
        var current = pid
        for _ in 0..<maxDepth where current > 1 {
            guard let info = processInfo(current) else { break }
            if tty == nil { tty = deviceName(info.kp_eproc.e_tdev) }
            if let path = executablePath(current), let bundle = outermostBundlePath(in: path) {
                topApp = bundle
            }
            current = info.kp_eproc.e_ppid
        }
        return Result(app: topApp.flatMap(bundleIdentifier), tty: tty)
    }

    // Only the outermost bundle counts: helpers nest inside the owning app's Frameworks directory.
    public static func outermostBundlePath(in executable: String) -> String? {
        guard executable.contains(appMarker),
              let end = executable.range(of: appSuffix + "/") else { return nil }
        return String(executable[..<end.upperBound].dropLast())
    }

    private static func processInfo(_ pid: pid_t) -> kinfo_proc? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return string(from: buffer)
    }

    private static func deviceName(_ device: Int32) -> String? {
        guard device != noDevice else { return nil }
        var buffer = [CChar](repeating: 0, count: deviceNameCapacity)
        guard devname_r(dev_t(device), S_IFCHR, &buffer, Int32(buffer.count)) != nil else { return nil }
        return devicePrefix + string(from: buffer)
    }

    private static func string(from buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func bundleIdentifier(_ bundlePath: String) -> String? {
        let plist = URL(fileURLWithPath: bundlePath).appendingPathComponent(infoPlistPath)
        guard let data = try? Data(contentsOf: plist), // lint-allow: sw-try-optional origin capture is best effort
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] // lint-allow: sw-try-optional origin capture is best effort
        else { return nil }
        return root[bundleIdentifierKey] as? String
    }
}
