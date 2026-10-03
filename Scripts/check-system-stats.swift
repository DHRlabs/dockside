import Foundation

@main
struct SystemStatsCheck {
    @MainActor
    static func main() async {
        var poller: SystemStatsPoller?
        var printed = false
        poller = SystemStatsPoller { reading in
            guard let cpu = reading.cpuPercent,
                  let gpu = reading.gpuPercent,
                  let memory = reading.memoryPercent,
                  let temperature = reading.temperatureCelsius else { return }
            print(String(format: "CPU %.1f%% GPU %.1f%% RAM %.1f%% CPU %.1f°C", cpu, gpu, memory, temperature))
            poller?.stop()
            printed = true
        }
        poller?.start()

        let deadline = Date().addingTimeInterval(8)
        while !printed && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        poller?.stop()
        if !printed {
            print("Live CPU, GPU, RAM, and temperature readings were not all available")
            exit(1)
        }
    }
}
