import AppKit
import SwiftUI

@MainActor
final class IndicatorWindow {
    private var panel: NSPanel?
    private weak var coordinator: PipelineCoordinator?

    func setCoordinator(_ coordinator: PipelineCoordinator) {
        self.coordinator = coordinator
    }

    enum IndicatorState {
        case recording
        case processing
        case ready

        var color: Color {
            switch self {
            case .recording: return .red
            case .processing: return .yellow
            case .ready: return .green
            }
        }

        var label: String {
            switch self {
            case .recording: return "Listening"
            case .processing: return "Processing"
            case .ready: return "Ready"
            }
        }
    }

    func show(state: IndicatorState) {
        if panel == nil {
            createPanel()
        }

        guard let panel, let coordinator else { return }

        let hostingView = NSHostingView(rootView: IndicatorView(state: state, coordinator: coordinator))
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)
        panel.contentView = hostingView
        panel.setContentSize(fittingSize)

        positionPanel(panel)

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Config.indicatorAnimationDuration
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Config.indicatorAnimationDuration
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.panel?.orderOut(nil)
            }
        })
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 30),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isExcludedFromWindowsMenu = true
        self.panel = panel
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.maxY - panelSize.height - Config.indicatorTopOffset
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Plus Sign Animation

private struct PlusSign: View {
    let color: Color
    let lineWidth: CGFloat = 1.5
    let size: CGFloat = 8

    @State private var verticalHeight: CGFloat = 0
    @State private var horizontalWidth: CGFloat = 0

    var body: some View {
        ZStack {
            // Vertical line
            Rectangle()
                .fill(color)
                .frame(width: lineWidth, height: verticalHeight)

            // Horizontal line
            Rectangle()
                .fill(color)
                .frame(width: horizontalWidth, height: lineWidth)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 0.15)) {
                verticalHeight = size
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeOut(duration: 0.15)) {
                    horizontalWidth = size
                }
            }
        }
    }
}

// MARK: - 3x3 Dot Grid Animation

private struct DotGrid: View {
    let activeColor: Color
    let mode: IndicatorWindow.IndicatorState
    let audioLevel: Float
    let dotSize: CGFloat = 2.5
    let spacing: CGFloat = 1

    @State private var litIndices: Set<Int> = []
    @State private var currentStep = 0

    private let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    // Center-out order: center first, then adjacent, then corners
    private static let centerOutOrder = [4, 1, 3, 5, 7, 0, 2, 6, 8]
    // Top-to-bottom order: row by row
    private static let topDownOrder = [0, 1, 2, 3, 4, 5, 6, 7, 8]

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(dotSize), spacing: spacing), count: 3)

        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(0..<9, id: \.self) { index in
                Circle()
                    .fill(litIndices.contains(index) ? activeColor : Color.white.opacity(0.15))
                    .frame(width: dotSize, height: dotSize)
                    .animation(.easeInOut(duration: 0.12), value: litIndices.contains(index))
            }
        }
        .onChange(of: audioLevel) { newLevel in
            if mode == .recording {
                updateLitDotsForAudioLevel(newLevel)
            }
        }
        .onReceive(timer) { _ in
            if mode == .processing {
                // Processing mode: continuous top-down animation
                if currentStep < Self.topDownOrder.count {
                    litIndices.insert(Self.topDownOrder[currentStep])
                    currentStep += 1
                } else {
                    litIndices = []
                    currentStep = 0
                }
            }
        }
    }

    private func updateLitDotsForAudioLevel(_ level: Float) {
        // Map audio level (0.0-1.0) to number of dots (0-9), with extra boost
        let boostedLevel = min(level * 1.5, 1.0)
        let numDots = Int(boostedLevel * 9.0)
        let dotsToLight = Set(Self.centerOutOrder.prefix(numDots))
        litIndices = dotsToLight
    }
}

// MARK: - Indicator View

private struct IndicatorView: View {
    let state: IndicatorWindow.IndicatorState
    @ObservedObject var coordinator: PipelineCoordinator

    var body: some View {
        HStack(spacing: 5) {
            if state == .ready {
                PlusSign(color: state.color)
            } else {
                DotGrid(activeColor: state.color, mode: state, audioLevel: coordinator.audioLevel)
            }

            Text(state.label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(state.color)
                .fixedSize()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: NSColor(white: 0.15, alpha: 1)))
        )
        .fixedSize()
    }
}
