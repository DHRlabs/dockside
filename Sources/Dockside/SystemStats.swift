import Darwin
import Foundation
import IOKit

public struct SystemStatsReading: Sendable {
    public var cpuPercent: Double?
    public var gpuPercent: Double?
    public var memoryPercent: Double?
    public var temperatureCelsius: Double?
    public var sampledAt: Date

    public init(
        cpuPercent: Double? = nil,
        gpuPercent: Double? = nil,
        memoryPercent: Double? = nil,
        temperatureCelsius: Double? = nil,
        sampledAt: Date = Date()
    ) {
        self.cpuPercent = Self.percentage(cpuPercent)
        self.gpuPercent = Self.percentage(gpuPercent)
        self.memoryPercent = Self.percentage(memoryPercent)
        self.temperatureCelsius = temperatureCelsius
        self.sampledAt = sampledAt
    }

    private static func percentage(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(100, max(0, value))
    }
}

@MainActor
public final class SystemStatsPoller {
    private let onUpdate: (SystemStatsReading) -> Void
    private var timer: DispatchSourceTimer?
    private var generation: UInt64 = 0

    public init(onUpdate: @escaping (SystemStatsReading) -> Void) {
        self.onUpdate = onUpdate
    }

    public func start() {
        guard timer == nil else { return }
        generation &+= 1
        let activeGeneration = generation
        let sampler = SystemStatsSampler()
        let source = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "Dockside.system-stats"))
        source.schedule(deadline: .now(), repeating: .seconds(2), leeway: .milliseconds(200))
        source.setEventHandler { [weak self, sampler] in
            let reading = sampler.sample()
            Task { @MainActor [weak self] in
                guard let self, self.generation == activeGeneration else { return }
                self.onUpdate(reading)
            }
        }
        timer = source
        source.resume()
    }

    public func stop() {
        generation &+= 1
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }
}

private struct CPUCounters {
    var states: [UInt32]
}

// All sampler state is confined to the poller's serial sampling queue.
private final class SystemStatsSampler: @unchecked Sendable {
    private var previousCPU: CPUCounters?
    private var previousGPU: (busy: UInt64, at: UInt64)?
    private var lastGPUPercent: Double?
    private let temperatures = SMCTemperatureReader()
    private var hostPort: mach_port_t = 0

    deinit {
        if hostPort != 0 { mach_port_deallocate(mach_task_self_, hostPort) }
    }

    func sample() -> SystemStatsReading {
        if hostPort == 0 { hostPort = mach_host_self() }
        let counters = readCPUCounters()
        let cpuPercent = counters.flatMap { current -> Double? in
            defer { previousCPU = current }
            guard let previousCPU,
                  previousCPU.states.count == current.states.count else { return nil }

            var totalDelta: UInt64 = 0
            var idleDelta: UInt64 = 0
            let stateCount = Int(CPU_STATE_MAX)
            for index in current.states.indices {
                let delta = UInt64(current.states[index] &- previousCPU.states[index])
                totalDelta += delta
                if index % stateCount == Int(CPU_STATE_IDLE) { idleDelta += delta }
            }
            guard totalDelta > 0 else { return nil }
            let busyDelta = totalDelta - min(totalDelta, idleDelta)
            return 100 * Double(busyDelta) / Double(totalDelta)
        }
        if counters == nil { previousCPU = nil }

        return SystemStatsReading(
            cpuPercent: cpuPercent,
            gpuPercent: readGPUPercent(),
            memoryPercent: readMemoryPercent(),
            temperatureCelsius: temperatures.readAverageCPU(),
            sampledAt: Date()
        )
    }

    private func readCPUCounters() -> CPUCounters? {
        var processorCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            hostPort,
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info,
              processorCount > 0,
              infoCount >= processorCount * natural_t(CPU_STATE_MAX) else { return nil }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(MemoryLayout<integer_t>.stride * Int(infoCount))
            )
        }

        let states = (0..<Int(infoCount)).map { UInt32(bitPattern: info[$0]) }
        return CPUCounters(states: states)
    }

    // Total GPU time every app has used so far, in nanoseconds, from the accelerator's per-app counters.
    private func readGPUBusyNanoseconds() -> UInt64? {
        var accelerators: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"), &accelerators) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(accelerators) }
        var total: UInt64 = 0
        var found = false
        var accelerator = IOIteratorNext(accelerators)
        while accelerator != 0 {
            defer { IOObjectRelease(accelerator); accelerator = IOIteratorNext(accelerators) }
            var children: io_iterator_t = 0
            guard IORegistryEntryCreateIterator(accelerator, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &children) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(children) }
            var child = IOIteratorNext(children)
            while child != 0 {
                defer { IOObjectRelease(child); child = IOIteratorNext(children) }
                let property = IORegistryEntryCreateCFProperty(child, "AppUsage" as CFString, kCFAllocatorDefault, 0)
                guard let apps = property?.takeRetainedValue() as? [[String: Any]] else { continue }
                found = true
                for app in apps { total &+= (app["accumulatedGPUTime"] as? NSNumber)?.uint64Value ?? 0 }
            }
        }
        return found ? total : nil
    }

    // ponytail: an app exiting drops its counter; that sample repeats the last percent instead of blanking.
    private func readGPUPercent() -> Double? {
        let now = DispatchTime.now().uptimeNanoseconds
        guard let busy = readGPUBusyNanoseconds() else { previousGPU = nil; return nil }
        defer { previousGPU = (busy, now) }
        guard let previousGPU, now > previousGPU.at else { return nil }
        guard busy >= previousGPU.busy else { return lastGPUPercent }
        lastGPUPercent = 100 * Double(busy - previousGPU.busy) / Double(now - previousGPU.at)
        return lastGPUPercent
    }

    private func readMemoryPercent() -> Double? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS, totalBytes > 0 else { return nil }

        let usedPages = Double(stats.active_count) + Double(stats.inactive_count) + Double(stats.speculative_count)
            + Double(stats.wire_count) + Double(stats.compressor_page_count)
            - Double(stats.purgeable_count) - Double(stats.external_page_count)
        let usedBytes = max(0, usedPages * Double(vm_page_size))
        return 100 * usedBytes / Double(totalBytes)
    }
}

enum SystemStatsTemperature {
    // Highest sensor value the reader keeps; also the full scale of the temperature bar.
    static let fullScale: Double = 120

    static func average(_ values: [Double]) -> Double? {
        let usable = values.filter { $0.isFinite && $0 > 0 && $0 < fullScale }
        guard !usable.isEmpty else { return nil }
        return usable.reduce(0, +) / Double(usable.count)
    }

    static func decode(type: String, bytes: [UInt8]) -> Double? {
        let value: Double
        switch type {
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            value = Double(Int16(bitPattern: raw)) / 256
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            value = Double(Float(bitPattern: bits))
        default:
            return nil
        }
        guard value.isFinite, value > 0, value < fullScale else { return nil }
        return value
    }
}

// SMC request layout and read calls adapted from Stats under its MIT license.
private final class SMCTemperatureReader {
    private typealias Bytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    private struct Version { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
    private struct PowerLimits { var version: UInt16 = 0; var length: UInt16 = 0; var cpu: UInt32 = 0; var gpu: UInt32 = 0; var memory: UInt32 = 0 }
    private struct KeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var attributes: UInt8 = 0 }
    private struct KeyData {
        var key: UInt32 = 0
        var version = Version()
        var powerLimits = PowerLimits()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private enum Command: UInt8 { case kernelIndex = 2; case readBytes = 5; case readKeyInfo = 9 }

    // These are the CPU average sensor keys enabled for this M5 Mac in Stats.
    private let cpuKeys = ["Tp00", "Tp04", "Tp0C", "Tp0G", "Tp0O", "Tp0R", "Tp0X", "Tp0a", "Tp0p", "Tp0u", "Tp0y"]
    private var connection: io_connect_t = 0

    deinit { close() }

    func readAverageCPU() -> Double? {
        guard openIfNeeded() else { return nil }
        let readings = cpuKeys.compactMap { key -> Double? in
            guard let value = read(key), let decoded = SystemStatsTemperature.decode(type: value.type, bytes: value.bytes) else { return nil }
            return decoded
        }
        if readings.isEmpty { close() }
        return SystemStatsTemperature.average(readings)
    }

    private func openIfNeeded() -> Bool {
        guard connection == 0 else { return true }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iterator) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }
        let service = IOIteratorNext(iterator)
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        return IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS
    }

    private func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        let keyBytes = Array(key.utf8)
        guard keyBytes.count == 4 else { return nil }
        var input = KeyData()
        var output = KeyData()
        input.key = keyBytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        input.data8 = Command.readKeyInfo.rawValue
        guard call(.kernelIndex, input: &input, output: &output) else { return nil }
        let size = Int(output.keyInfo.dataSize)
        guard (1...32).contains(size) else { return nil }
        let dataType = output.keyInfo.dataType

        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = Command.readBytes.rawValue
        guard call(.kernelIndex, input: &input, output: &output) else { return nil }
        let type = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: dataType >> $0) }
        let typeString = String(bytes: type, encoding: .ascii) ?? ""
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(size)) }
        return (typeString, bytes)
    }

    private func call(_ command: Command, input: inout KeyData, output: inout KeyData) -> Bool {
        var outputSize = MemoryLayout<KeyData>.stride
        let result = IOConnectCallStructMethod(
            connection,
            UInt32(command.rawValue),
            &input,
            MemoryLayout<KeyData>.stride,
            &output,
            &outputSize
        )
        return result == KERN_SUCCESS && outputSize == MemoryLayout<KeyData>.stride && output.result == 0
    }

    private func close() {
        guard connection != 0 else { return }
        IOServiceClose(connection)
        connection = 0
    }
}
