import SwiftUI

struct SystemMonitorView: View {
    @ObservedObject var service: SystemMonitorService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("System Monitor".localized, systemImage: "cpu")
                    .font(.caption.bold())
                Spacer()
                Button(action: { service.stopMonitoring() }) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 2)
            
            Group {
                MonitorRow(label: "Host", value: service.stats.hostname)
                MonitorRow(label: "OS", value: service.stats.osName)
                MonitorRow(label: "CPU", value: service.stats.cpuModel)
                MonitorRow(label: "Uptime", value: service.stats.uptime)
            }
            
            Divider()
            
            VStack(spacing: 8) {
                // CPU with Sparkline
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("CPU").font(.caption2).foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f%%", service.stats.cpuUsage * 100)).font(.caption2.monospaced())
                    }
                    Sparkline(data: service.stats.cpuHistory, color: .blue)
                        .frame(height: 24)
                }
                
                // Memory with Sparkline
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Mem").font(.caption2).foregroundColor(.secondary)
                        Spacer()
                        Text(service.stats.memoryLabel.split(separator: " ").first ?? "-").font(.caption2.monospaced())
                    }
                    Sparkline(data: service.stats.memHistory, color: .green)
                        .frame(height: 24)
                }
                
                Divider()
                
                // Network Traffic
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Network").font(.caption2).foregroundColor(.secondary)
                        Spacer()
                        let down = service.stats.netDownHistory.last ?? 0
                        let up = service.stats.netUpHistory.last ?? 0
                        Text("↓\(formatBytes(down))/s ↑\(formatBytes(up))/s").font(.system(size: 9, design: .monospaced))
                    }
                    ZStack {
                        Sparkline(data: service.stats.netDownHistory, color: .purple)
                        Sparkline(data: service.stats.netUpHistory, color: .pink.opacity(0.7))
                    }
                    .frame(height: 24)
                }
                
                // Disk IO
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Disk IO").font(.caption2).foregroundColor(.secondary)
                        Spacer()
                        let read = service.stats.diskReadHistory.last ?? 0
                        let write = service.stats.diskWriteHistory.last ?? 0
                        Text("R:\(formatBytes(read))/s W:\(formatBytes(write))/s").font(.system(size: 9, design: .monospaced))
                    }
                    ZStack {
                        Sparkline(data: service.stats.diskReadHistory, color: .orange)
                        Sparkline(data: service.stats.diskWriteHistory, color: .yellow.opacity(0.7))
                    }
                    .frame(height: 24)
                }
            }
        }
        .padding(12)
        .frame(width: 260)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
    
    private func formatBytes(_ bytes: Double) -> String {
        if bytes < 1024 { return String(format: "%.0fB", bytes) }
        if bytes < 1024 * 1024 { return String(format: "%.1fK", bytes / 1024) }
        return String(format: "%.1fM", bytes / (1024 * 1024))
    }
}

struct Sparkline: View {
    let data: [Double]
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            Path { path in
                guard data.count > 1 else { return }
                
                let maxVal = data.max() ?? 1.0
                let normalizedMax = maxVal == 0 ? 1.0 : maxVal
                
                let stepX = geo.size.width / CGFloat(data.count - 1)
                
                for (i, val) in data.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = geo.size.height * (1.0 - CGFloat(val / normalizedMax))
                    
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color, lineWidth: 1.5)
            
            // Fill area
            Path { path in
                guard data.count > 1 else { return }
                let maxVal = data.max() ?? 1.0
                let normalizedMax = maxVal == 0 ? 1.0 : maxVal
                let stepX = geo.size.width / CGFloat(data.count - 1)
                
                path.move(to: CGPoint(x: 0, y: geo.size.height))
                for (i, val) in data.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = geo.size.height * (1.0 - CGFloat(val / normalizedMax))
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                path.closeSubpath()
            }
            .fill(LinearGradient(colors: [color.opacity(0.3), color.opacity(0.0)], startPoint: .top, endPoint: .bottom))
        }
    }
}

struct MonitorRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)
            Text(value)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
