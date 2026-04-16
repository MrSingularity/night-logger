import SwiftUI
import Combine

struct RecordingView: View {
    @EnvironmentObject var store: SessionStore
    @StateObject private var classifier = AudioClassifier()

    @State private var isRecording    = false
    @State private var errorMessage:    String?
    @State private var recentEvents:  [AudioEvent] = []
    @State private var pulseAnimation = false
    @State private var currentTime    = Date()

    let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color("BackgroundNight").ignoresSafeArea()

            VStack(spacing: 0) {

                // MARK: Clock — fixed at top
                VStack(spacing: 4) {
                    Text(currentTime, format: .dateTime.hour().minute().second())
                        .font(.system(size: 56, weight: .thin, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(currentTime, format: .dateTime.weekday(.wide).day().month())
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.4))
                        .textCase(.uppercase)
                        .tracking(2)
                }
                .padding(.top, 48)
                .padding(.bottom, 32)

                // MARK: Pulse indicator — fixed height, never moves
                ZStack {
                    if isRecording {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .stroke(Color("AccentNight").opacity(0.15 - Double(i) * 0.04), lineWidth: 1)
                                .frame(width: CGFloat(120 + i * 50), height: CGFloat(120 + i * 50))
                                .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                                .animation(
                                    .easeInOut(duration: 1.8)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.3),
                                    value: pulseAnimation
                                )
                        }
                    }
                    Circle()
                        .fill(isRecording ? Color("AccentNight").opacity(0.2) : Color.white.opacity(0.05))
                        .frame(width: 120, height: 120)
                    Image(systemName: isRecording ? "waveform" : "moon.zzz")
                        .font(.system(size: 42))
                        .foregroundStyle(isRecording ? Color("AccentNight") : .white.opacity(0.3))
                        .symbolEffect(.variableColor, isActive: isRecording)
                }
                .frame(width: 220, height: 220) // fixed size — never grows or shrinks

                // MARK: Status label — fixed height
                Group {
                    if let err = errorMessage {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red.opacity(0.8))
                    } else if isRecording {
                        let count = store.activeSession?.events.filter({ !$0.isDismissed }).count ?? 0
                        VStack(spacing: 4) {
                            Text("LISTENING")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(4)
                                .foregroundStyle(Color("AccentNight"))
                            Text("\(count) event\(count == 1 ? "" : "s") recorded")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    } else {
                        Text("Tap to start overnight recording")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .frame(height: 44) // fixed height — text changes don't affect layout

                // MARK: Recent detections — fixed area at bottom, scrollable
                // Using a fixed frame so the button never moves
                VStack(alignment: .leading, spacing: 0) {
                    if !recentEvents.isEmpty {
                        Text("RECENT DETECTIONS")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(3)
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(.horizontal, 24)
                            .padding(.bottom, 8)
                            .padding(.top, 16)

                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 8) {
                                ForEach(recentEvents) { event in
                                    EventRow(event: event)
                                        .padding(.horizontal, 24)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220) // fixed height — button stays put regardless of events

                // MARK: Record / Stop button — always at bottom
                Button(action: toggleRecording) {
                    Text(isRecording ? "Stop Recording" : "Start Recording")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isRecording ? .white : Color("BackgroundNight"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(isRecording ? Color.red.opacity(0.85) : Color("AccentNight"))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 90) // above tab bar
            }
        }
        .onReceive(clockTimer) { time in currentTime = time }
        .onAppear { setupClassifier() }
    }

    // MARK: - Helpers

    private func setupClassifier() {
        classifier.onDetection = { result, clipPath in
            guard result.confidence >= 0.45 else { return }
            let event = AudioEvent(
                timestamp:     .now,
                soundClass:    result.soundClass,
                confidence:    result.confidence,
                audioClipPath: clipPath
            )
            store.appendEvent(event)
            withAnimation(.spring(duration: 0.3)) {
                recentEvents.insert(event, at: 0)
                if recentEvents.count > 4 { recentEvents.removeLast() }
            }
        }
    }

    private func toggleRecording() {
        if isRecording {
            classifier.stopListening()
            store.stopSession()
            isRecording    = false
            pulseAnimation = false
            recentEvents   = []
        } else {
            store.startSession()
            do {
                try classifier.startListening()
                isRecording    = true
                pulseAnimation = true
                errorMessage   = nil
            } catch {
                errorMessage = error.localizedDescription
                store.stopSession()
            }
        }
    }
}

// MARK: - Event Row

private struct EventRow: View {
    let event: AudioEvent

    var body: some View {
        HStack(spacing: 12) {
            Text(event.soundClass.emoji)
                .font(.title3)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.soundClass.rawValue)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                    if event.isUncertain {
                        Text("?")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text(event.timestamp, format: .dateTime.hour().minute().second())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer()

            // Confidence pill
            Text("\(Int(event.confidence * 100))%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(event.confidence >= 0.7 ? Color.green : Color.orange)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background((event.confidence >= 0.7 ? Color.green : Color.orange).opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
