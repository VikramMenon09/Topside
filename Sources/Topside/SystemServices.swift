import AppKit
import SwiftUI
import IOKit.ps

// MARK: - Battery

final class BatteryService: ObservableObject {
    static let shared = BatteryService()
    @Published var percent = 100
    @Published var charging = false
    @Published var pluggedIn = false
    @Published var hasBattery = false
    @Published var timeRemaining = ""
    private var first = true

    func start() {
        refresh()
        let src = IOPSNotificationCreateRunLoopSource({ _ in BatteryService.shared.refresh() }, nil).takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
    }

    func refresh() {
        let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [CFTypeRef]
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCap = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let pct = maxCap > 0 ? Int((Double(cur) / Double(maxCap) * 100).rounded()) : cur
            let plugged = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let chg = d[kIOPSIsChargingKey] as? Bool ?? false
            let mins = (plugged ? d[kIOPSTimeToFullChargeKey] : d[kIOPSTimeToEmptyKey]) as? Int ?? -1
            onMain {
                if !self.first, plugged != self.pluggedIn {
                    ActivityCenter.shared.show(Toast(icon: plugged ? "bolt.fill" : "battery.75percent",
                                                     text: plugged ? "Charging \(pct)%" : "On battery \(pct)%",
                                                     tint: plugged ? .green : .white))
                }
                if !self.first, !plugged, pct <= 10, self.percent > 10 {
                    ActivityCenter.shared.show(Toast(icon: "battery.25percent", text: "Low battery \(pct)%", tint: .red))
                }
                self.first = false
                self.hasBattery = true
                self.percent = pct
                self.charging = chg
                self.pluggedIn = plugged
                self.timeRemaining = mins > 0 ? "\(mins / 60)h \(mins % 60)m " + (plugged ? "to full" : "left") : ""
            }
            return
        }
        onMain { self.first = false }
    }

    var icon: String {
        if charging || pluggedIn { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

// MARK: - Downloads

struct ActiveDownload: Identifiable, Equatable {
    var id: String
    var name: String
    var bytes: Int64
}

/// Watches ~/Downloads for in-progress files (Safari, Chrome, Firefox naming) when enabled.
final class DownloadsService: ObservableObject {
    static let shared = DownloadsService()
    @Published var active: [ActiveDownload] = []
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.scan() }
    }

    private func scan() {
        guard Prefs.bool("watchDownloads") else {
            if !active.isEmpty { active = [] }
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            guard let dir = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first,
                  let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return }
            var now: [ActiveDownload] = []
            for u in items where ["crdownload", "download", "part"].contains(u.pathExtension.lowercased()) {
                var size = Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                if u.pathExtension.lowercased() == "download",
                   let inner = try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: [.fileSizeKey]) {
                    size = inner.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
                }
                now.append(ActiveDownload(id: u.path, name: u.deletingPathExtension().lastPathComponent, bytes: size))
            }
            onMain {
                let before = Set(self.active.map(\.id))
                let after = Set(now.map(\.id))
                for d in now where !before.contains(d.id) {
                    ActivityCenter.shared.show(Toast(icon: "arrow.down.circle.fill", text: "Downloading", tint: .blue))
                    _ = d
                }
                for d in self.active where !after.contains(d.id) {
                    ActivityCenter.shared.show(Toast(icon: "checkmark.circle.fill", text: d.name, tint: .green))
                }
                if self.active != now { self.active = now }
            }
        }
    }
}

// MARK: - Basic system checks

final class SystemStats: ObservableObject {
    static let shared = SystemStats()
    @Published var cpu = 0.0
    @Published var memory = 0.0
    @Published var diskFree = ""
    private var lastTicks: (busy: Double, total: Double)?

    func refresh() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        if kr == KERN_SUCCESS {
            let user = Double(info.cpu_ticks.0), sys = Double(info.cpu_ticks.1), idle = Double(info.cpu_ticks.2), nice = Double(info.cpu_ticks.3)
            let busy = user + sys + nice, total = busy + idle
            if let l = lastTicks, total > l.total { cpu = (busy - l.busy) / (total - l.total) }
            lastTicks = (busy, total)
        }

        var vm = vm_statistics64()
        var vcount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vcount)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vcount) }
        }
        if vr == KERN_SUCCESS {
            let page = Double(vm_kernel_page_size)
            let used = Double(vm.active_count + vm.wire_count + vm.compressor_page_count) * page
            memory = used / Double(ProcessInfo.processInfo.physicalMemory)
        }

        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage {
            diskFree = ByteCountFormatter.string(fromByteCount: v, countStyle: .file)
        }
    }
}
