import SwiftUI

struct AIStep: Identifiable, Decodable {
    let id = UUID()
    let desc: String
    let cmd: String
    var isExecuted: Bool = false // Local state for UI
    
    private enum CodingKeys: String, CodingKey {
        case desc, cmd
    }
}

struct TerminalAIOverlay: View {
    @Binding var isPresented: Bool
    @Binding var prompt: String
    @Binding var isGenerating: Bool
    
    // New: Steps support
    @Binding var steps: [AIStep]
    let onGenerate: () -> Void
    let onExecuteStep: (AIStep) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                // Input Header with TextEditor
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                        Text("AI Assistant".localized)
                            .font(.caption.bold())
                        Spacer()
                        
                        if isGenerating {
                            ProgressView().scaleEffect(0.5)
                        } else if !steps.isEmpty {
                            Button("Clear".localized) {
                                withAnimation {
                                    steps = []
                                    prompt = ""
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        
                        Button(action: { withAnimation { isPresented = false } }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Text Area
                    ZStack(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text("Describe what you want to do...".localized)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        
                        TextEditor(text: $prompt)
                            .font(.system(size: 12))
                            .frame(height: 80)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                    }
                    .padding(4)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
                    
                    if !isGenerating {
                        Button(action: onGenerate) {
                            Text("Generate Command".localized)
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(DesignSystem.Colors.blue)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                
                // Steps List
                if !steps.isEmpty {
                    Divider()
                    List {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                            HStack {
                                Image(systemName: step.isExecuted ? "checkmark.circle.fill" : "\(index + 1).circle")
                                    .foregroundColor(step.isExecuted ? .green : .secondary)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.desc)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(DesignSystem.Colors.text)
                                    Text(step.cmd)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                Button(action: { onExecuteStep(step) }) {
                                    Image(systemName: "play.fill")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                        .padding(4)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(4)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(height: min(CGFloat(steps.count * 44 + 20), 200)) 
                    .listStyle(.plain)
                }
            }
            .background(DesignSystem.Colors.surface)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.2), radius: 15, x: 0, y: 10)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            
            // Arrow pointing down (Aligned to right to point at button)
            HStack {
                Spacer()
                Triangle()
                    .fill(DesignSystem.Colors.surface)
                    .frame(width: 14, height: 8)
                    .rotationEffect(.degrees(180))
                Spacer().frame(width: 40)
            }
            .padding(.bottom, -8)
            .zIndex(2)
        }
        .frame(width: 320)
    }
}

// Custom Triangle Shape for the arrow
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
