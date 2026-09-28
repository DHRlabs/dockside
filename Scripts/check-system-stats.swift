import Foundation

@main
struct SystemStatsCheck {
    @MainActor
    static func main() async {
        assert(SystemStatsTemperature.average([]) == nil)
        assert(SystemStatsTemperature.decode(type: "sp78", bytes: [0x19]) == nil)
        assert(SystemStatsTemperature.decode(type: "flt ", bytes: [0, 0, 0]) == nil)
        assert(SystemStatsTemperature.decode(type: "bad!", bytes: [0, 0, 0, 0]) == nil)
        assert(SystemStatsTemperature.decode(type: "sp78", bytes: [0, 0]) == nil)
        assert(SystemStatsTemperature.average([0, 50]) == 50)
        assert(SystemStatsTemperature.decode(type: "flt ", bytes: [0, 0, 0x80, 0x7f]) == nil)
        assert(SystemStatsTemperature.decode(type: "sp78", bytes: [0x19, 0]) == 25)

        var poller: SystemStatsPoller?
        var printed = false
        poller = SystemStatsPoller { reading in
            guard let cpu = reading.cpuPercent,
                  let memory = reading.memoryPercent,
                  let temperature = reading.temperatureCelsius else { return }
            print(String(format: "CPU %.1f%% RAM %.1f%% CPU %.1f°C", cpu, memory, temperature))
            poller?.stop()
            printed = true
        }
        poller?.start()

        let deadline = Date().addingTimeInterval(8)
        while !printed && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        poller?.stop()
        assert(printed, "Live CPU, RAM, and temperature readings were not all available")
    }
}
