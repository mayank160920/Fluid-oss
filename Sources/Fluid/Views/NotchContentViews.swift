//
//  NotchContentViews.swift
//  Fluid
//
//  Created by Assistant
//

import SwiftUI
import Combine

// MARK: - Observable state for notch content (Singleton)

@MainActor
class NotchContentState: ObservableObject {
    static let shared = NotchContentState()
    
    @Published var transcriptionText: String = ""
    @Published var mode: OverlayMode = .dictation
    
    // Cached transcription lines to avoid recomputing on every render
    @Published private(set) var cachedLine1: String = ""
    @Published private(set) var cachedLine2: String = ""
    
    private init() {}
    
    /// Update transcription and recompute cached lines
    func updateTranscription(_ text: String) {
        guard text != transcriptionText else { return }
        transcriptionText = text
        recomputeTranscriptionLines()
    }
    
    /// Recompute cached transcription lines (called only when text changes)
    private func recomputeTranscriptionLines() {
        let text = transcriptionText
        
        guard !text.isEmpty else {
            cachedLine1 = ""
            cachedLine2 = ""
            return
        }
        
        // Show last ~100 characters
        let maxChars = 100
        let displayText = text.count > maxChars ? String(text.suffix(maxChars)) : text
        
        // Split into words
        let words = displayText.split(separator: " ").map(String.init)
        
        if words.count <= 6 {
            // Short: only line 2
            cachedLine1 = ""
            cachedLine2 = displayText
        } else {
            // Long: split roughly in half
            let midPoint = words.count / 2
            cachedLine1 = words[..<midPoint].joined(separator: " ")
            cachedLine2 = words[midPoint...].joined(separator: " ")
        }
    }
}

// MARK: - Shared Mode Color Helper

extension OverlayMode {
    /// Mode-specific color for notch UI elements
    var notchColor: Color {
        switch self {
        case .dictation:
            return Color.white.opacity(0.85)
        case .rewrite:
            return Color(red: 0.45, green: 0.55, blue: 1.0) // Lighter blue
        case .write:
            return Color(red: 0.4, green: 0.6, blue: 1.0)   // Blue
        case .command:
            return Color(red: 1.0, green: 0.35, blue: 0.35) // Red
        }
    }
}

// MARK: - Expanded View (Main Content) - Minimal Design

struct NotchExpandedView: View {
    let audioPublisher: AnyPublisher<CGFloat, Never>
    @ObservedObject private var contentState = NotchContentState.shared
    
    private var modeColor: Color {
        contentState.mode.notchColor
    }
    
    private var modeLabel: String {
        switch contentState.mode {
        case .dictation: return "Dictate"
        case .rewrite: return "Rewrite"
        case .write: return "Write"
        case .command: return "Command"
        }
    }
    
    private var hasTranscription: Bool {
        !contentState.transcriptionText.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Visualization + Mode label row
            HStack(spacing: 6) {
                NotchWaveformView(audioPublisher: audioPublisher, color: modeColor)
                    .frame(width: 80, height: 22)
                
                // Mode label
                Text(modeLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(modeColor)
                    .opacity(0.9)
            }
            
            // Transcription preview (single line, minimal)
            if hasTranscription {
                Text(contentState.cachedLine2)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 180)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hasTranscription)
        .animation(.easeInOut(duration: 0.2), value: contentState.mode)
    }
}

// MARK: - Minimal Notch Waveform (Color-matched)

struct NotchWaveformView: View {
    let audioPublisher: AnyPublisher<CGFloat, Never>
    let color: Color
    
    @StateObject private var data: AudioVisualizationData
    @State private var barHeights: [CGFloat] = Array(repeating: 3, count: 7)
    
    private let barCount = 7
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 4
    private let minHeight: CGFloat = 3
    private let maxHeight: CGFloat = 20
    
    init(audioPublisher: AnyPublisher<CGFloat, Never>, color: Color) {
        self.audioPublisher = audioPublisher
        self.color = color
        self._data = StateObject(wrappedValue: AudioVisualizationData(audioLevelPublisher: audioPublisher))
    }
    
    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(color)
                    .frame(width: barWidth, height: barHeights[index])
                    .shadow(color: color.opacity(0.4), radius: 2, x: 0, y: 0)
            }
        }
        .onChange(of: data.audioLevel) { level in
            updateBars(level: level)
        }
        .onAppear {
            // Initialize with idle animation
            updateBars(level: 0)
        }
    }
    
    private func updateBars(level: CGFloat) {
        let normalizedLevel = min(max(level, 0), 1)
        let isActive = normalizedLevel > 0.02
        
        withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
            for i in 0..<barCount {
                let centerDistance = abs(CGFloat(i) - CGFloat(barCount - 1) / 2)
                let centerFactor = 1.0 - (centerDistance / CGFloat(barCount / 2)) * 0.4
                
                if isActive {
                    let randomVariation = CGFloat.random(in: 0.7...1.0)
                    barHeights[i] = minHeight + (maxHeight - minHeight) * normalizedLevel * centerFactor * randomVariation
                } else {
                    // Subtle idle pulse
                    let idleVariation = CGFloat.random(in: 0.8...1.2)
                    barHeights[i] = minHeight * idleVariation
                }
            }
        }
    }
}

// MARK: - Compact Views (Small States)

struct NotchCompactLeadingView: View {
    @ObservedObject private var contentState = NotchContentState.shared
    @State private var isPulsing = false
    
    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(contentState.mode.notchColor)
            .scaleEffect(isPulsing ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
            .onDisappear { isPulsing = false }
    }
}

struct NotchCompactTrailingView: View {
    @ObservedObject private var contentState = NotchContentState.shared
    @State private var isPulsing = false
    
    var body: some View {
        Circle()
            .fill(contentState.mode.notchColor)
            .frame(width: 5, height: 5)
            .opacity(isPulsing ? 0.5 : 1.0)
            .scaleEffect(isPulsing ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
            .onDisappear { isPulsing = false }
    }
}
