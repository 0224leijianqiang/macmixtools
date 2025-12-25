import Foundation
import Combine
import Citadel

struct SystemStats {
    var osName: String = "-"
    var kernel: String = "-"
    var hostname: String = "-"
    var arch: String = "-"
    var cpuModel: String = "-"
    var cpuUsage: Double = 0.0 // Changed to Double for history
    var memoryUsage: Double = 0.0
    var memoryLabel: String = "- / -"
    var swapUsage: Double = 0.0
    var diskUsage: String = "-"
    var uptime: String = "-"
    
    // History for Sparklines
    var cpuHistory: [Double] = Array(repeating: 0, count: 20)
    var memHistory: [Double] = Array(repeating: 0, count: 20)
    var netUpHistory: [Double] = Array(repeating: 0, count: 20)
    var netDownHistory: [Double] = Array(repeating: 0, count: 20)
    var diskReadHistory: [Double] = Array(repeating: 0, count: 20)
    var diskWriteHistory: [Double] = Array(repeating: 0, count: 20)
}

class SystemMonitorService: ObservableObject {
    @Published var stats = SystemStats()
    @Published var isVisible = false
    
    private let runner: SSHRunner
    private var timer: Timer?
    private var isFetching = false
    
    // For calculating rates
    private var lastNetDown: Double = 0
    private var lastNetUp: Double = 0
    private var lastDiskRead: Double = 0
    private var lastDiskWrite: Double = 0
    private var lastFetchTime: Date = Date()
    
    init(runner: SSHRunner) {
        self.runner = runner
    }
    
    // ... startMonitoring, stopMonitoring, toggle remains same ...
    
    func startMonitoring() {
        guard timer == nil else { return }
        isVisible = true // Set visible immediately to show the panel
        
        // Fetch data in background so UI doesn't wait
        Task {
            fetchStats()
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.fetchStats()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isVisible = false
    }
    
    func toggle() {
        if isVisible {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }
    
    private func fetchStats() {
        guard !isFetching else { return }
        isFetching = true
        
        Task {
            do {
                // Faster CPU fetch using /proc/stat instead of top
                let script = """
                echo "OS:$(grep -w PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')"
                echo "KERNEL:$(uname -r)"
                echo "ARCH:$(uname -m)"
                echo "HOSTNAME:$(hostname)"
                echo "CPU_MODEL:$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)"
                echo "MEM:$(free -m 2>/dev/null | grep Mem | awk '{print $2,$3}')"
                echo "SWAP:$(free -m 2>/dev/null | grep Swap | awk '{print $2,$3}')"
                echo "DISK:$(df -h / 2>/dev/null | tail -1 | awk '{print $5}')"
                echo "UPTIME:$(uptime -p 2>/dev/null)"
                echo "CPU_STAT:$(grep 'cpu ' /proc/stat 2>/dev/null)"
                echo "NET:$(grep -E 'eth0|enp|ens|wlan' /proc/net/dev 2>/dev/null | head -1 | awk '{print $2,$10}')"
                echo "IO:$(cat /proc/diskstats 2>/dev/null | grep -E 'sda|vda|nvme0n1' | head -1 | awk '{print $6,$10}')"
                """
                
                let output = try await runner.executeCommand(script)
                
                await MainActor.run {
                    self.parseOutput(output)
                    self.isFetching = false
                }
            } catch {
                await MainActor.run {
                    self.isFetching = false
                }
            }
        }
    }
    
    private var lastTotalCpu: Double = 0
    private var lastIdleCpu: Double = 0
    
    private func parseOutput(_ output: String) {
        var newStats = self.stats
        let currentTime = Date()
        let timeInterval = currentTime.timeIntervalSince(self.lastFetchTime)
        self.lastFetchTime = currentTime
        
        output.enumerateLines { [weak self] line, _ in
            guard let self = self else { return }
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let key = parts[0]
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                
                switch key {
                case "OS": newStats.osName = value.isEmpty ? "Linux" : value
                case "KERNEL": newStats.kernel = value
                case "ARCH": newStats.arch = value
                case "HOSTNAME": newStats.hostname = value
                case "CPU_MODEL": newStats.cpuModel = value
                case "DISK": newStats.diskUsage = value
                case "UPTIME": newStats.uptime = value.replacingOccurrences(of: "up ", with: "")
                case "CPU_STAT":
                    // cpu  user nice system idle iowait ...
                    let cpuParts = value.split(separator: " ").compactMap { Double($0) }
                    if cpuParts.count >= 4 {
                        let user = cpuParts[0]
                        let nice = cpuParts[1]
                        let system = cpuParts[2]
                        let idle = cpuParts[3]
                        let total = user + nice + system + idle
                        
                        if self.lastTotalCpu > 0 {
                            let totalDiff = total - self.lastTotalCpu
                            let idleDiff = idle - self.lastIdleCpu
                            if totalDiff > 0 {
                                newStats.cpuUsage = (totalDiff - idleDiff) / totalDiff
                            }
                        }
                        self.lastTotalCpu = total
                        self.lastIdleCpu = idle
                    }
                case "MEM":
                    let memParts = value.split(separator: " ").compactMap { Double($0) }
                    if memParts.count == 2 {
                        let total = memParts[0]
                        let used = memParts[1]
                        if total > 0 {
                            newStats.memoryUsage = used / total
                            newStats.memoryLabel = "\(Int(used))M / \(Int(total))M"
                        }
                    }
                case "SWAP":
                    let swapParts = value.split(separator: " ").compactMap { Double($0) }
                    if swapParts.count == 2 {
                        let total = swapParts[0]
                        let used = swapParts[1]
                        if total > 0 {
                            newStats.swapUsage = used / total
                        }
                    }
                case "NET":
                    let netParts = value.split(separator: " ").compactMap { Double($0) }
                    if netParts.count == 2 {
                        let down = netParts[0]
                        let up = netParts[1]
                        if self.lastNetDown > 0 {
                            let downRate = max(0, (down - self.lastNetDown) / timeInterval)
                            let upRate = max(0, (up - self.lastNetUp) / timeInterval)
                            
                            newStats.netDownHistory.removeFirst()
                            newStats.netDownHistory.append(downRate)
                            newStats.netUpHistory.removeFirst()
                            newStats.netUpHistory.append(upRate)
                        }
                        self.lastNetDown = down
                        self.lastNetUp = up
                    }
                case "IO":
                    let ioParts = value.split(separator: " ").compactMap { Double($0) }
                    if ioParts.count == 2 {
                        let read = ioParts[0] * 512 // sectors to bytes
                        let write = ioParts[1] * 512
                        if self.lastDiskRead > 0 {
                            let readRate = max(0, (read - self.lastDiskRead) / timeInterval)
                            let writeRate = max(0, (write - self.lastDiskWrite) / timeInterval)
                            
                            newStats.diskReadHistory.removeFirst()
                            newStats.diskReadHistory.append(readRate)
                            newStats.diskWriteHistory.removeFirst()
                            newStats.diskWriteHistory.append(writeRate)
                        }
                        self.lastDiskRead = read
                        self.lastDiskWrite = write
                    }
                default: break
                }
            }
        }
        
        // Update general histories
        newStats.cpuHistory.removeFirst()
        newStats.cpuHistory.append(newStats.cpuUsage)
        newStats.memHistory.removeFirst()
        newStats.memHistory.append(newStats.memoryUsage)
        
        self.stats = newStats
    }
}
