import Foundation
import IOKit
import Metal

struct MachineAssessment: Sendable {
    let modelIdentifier: String
    let chipName: String
    let totalMemoryGB: Double
    let availableMemoryGB: Double
    let cpuCoreCount: Int
    let performanceCoreCount: Int
    let efficiencyCoreCount: Int
    let memoryBandwidthGBs: Double

    static let placeholder = MachineAssessment(
        modelIdentifier: "Detecting...",
        chipName: "Detecting...",
        totalMemoryGB: 0,
        availableMemoryGB: 0,
        cpuCoreCount: 0,
        performanceCoreCount: 0,
        efficiencyCoreCount: 0,
        memoryBandwidthGBs: 0
    )
}

enum SystemAssessment {
    static func collect() async -> MachineAssessment {
        await Task.detached(priority: .userInitiated) {
            let modelIdentifier = readSysctlString("hw.model") ?? "Unknown Mac"
            let chipName = readChipName()
            let totalMemoryBytes = ProcessInfo.processInfo.physicalMemory
            let availableMemoryBytes = readAvailableMemoryBytes() ?? totalMemoryBytes / 3
            let cpuCores = ProcessInfo.processInfo.processorCount
            let performanceCores = readSysctlInt("hw.perflevel0.physicalcpu") ?? max(1, cpuCores / 2)
            let efficiencyCores = readSysctlInt("hw.perflevel1.physicalcpu") ?? max(0, cpuCores - performanceCores)
            let bandwidth = estimateMemoryBandwidthGBs(chipName: chipName)

            return MachineAssessment(
                modelIdentifier: modelIdentifier,
                chipName: chipName,
                totalMemoryGB: bytesToGB(totalMemoryBytes),
                availableMemoryGB: bytesToGB(availableMemoryBytes),
                cpuCoreCount: cpuCores,
                performanceCoreCount: performanceCores,
                efficiencyCoreCount: efficiencyCores,
                memoryBandwidthGBs: bandwidth
            )
        }.value
    }

    private static func readChipName() -> String {
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            return metalDevice.name
        }
        if let cpuBrand = readSysctlString("machdep.cpu.brand_string"), !cpuBrand.isEmpty {
            return cpuBrand
        }
        return "Unknown Chip"
    }

    private static func bytesToGB(_ bytes: UInt64) -> Double {
        Double(bytes) / 1_073_741_824.0
    }

    private static func readAvailableMemoryBytes() -> UInt64? {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &vmStats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }
        let freeAndInactivePages = UInt64(vmStats.free_count + vmStats.inactive_count)
        return freeAndInactivePages * UInt64(pageSize)
    }

    private static func readSysctlString(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func readSysctlInt(_ key: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(key, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    // Conservative memory bandwidth estimates used for rough throughput guidance.
    private static func estimateMemoryBandwidthGBs(chipName: String) -> Double {
        let normalized = chipName.lowercased()
        if normalized.contains("m3 ultra") { return 800 }
        if normalized.contains("m3 max") { return 400 }
        if normalized.contains("m3 pro") { return 150 }
        if normalized.contains("m3") { return 100 }
        if normalized.contains("m2 ultra") { return 800 }
        if normalized.contains("m2 max") { return 400 }
        if normalized.contains("m2 pro") { return 200 }
        if normalized.contains("m2") { return 100 }
        if normalized.contains("m1 ultra") { return 800 }
        if normalized.contains("m1 max") { return 400 }
        if normalized.contains("m1 pro") { return 200 }
        if normalized.contains("m1") { return 68 }
        return 90
    }
}
