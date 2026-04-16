import SwiftUI
import Charts
import AVFoundation

// MARK: - Dashboard root

struct DashboardView: View {
    @EnvironmentObject var store: SessionStore
    @State private var selectedSession: NightSession?

    var body: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty {
                    EmptyDashboard()
                } else {
                    SessionListView(selectedSession: $selectedSession)
                }
            }
            .navigationTitle("Dashboard")
            .navigationDestination(item: $selectedSession) { session in
                SessionDetailView(sessionID: session.id)
            }
        }
    }
}

// MARK: - Empty state

private struct EmptyDashboard: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.stars")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No sessions yet")
                .font(.title2).fontWeight(.semibold)
            Text("Start a recording tonight to see\nyour sleep sound summary here.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - Session list

private struct SessionListView: View {
    @EnvironmentObject var store: SessionStore
    @Binding var selectedSession: NightSession?

    var body: some View {
        List {
            ForEach(store.sessions) { session in
                Button { selectedSession = session } label: {
                    SessionRow(session: session)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                offsets.forEach { store.deleteSession(store.sessions[$0]) }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct SessionRow: View {
    let session: NightSession
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.startDate, format: .dateTime.weekday(.wide).day().month())
                    .font(.headline)
                Spacer()
                if session.endDate == nil {
                    Text("LIVE").font(.caption2).fontWeight(.bold)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.red.opacity(0.15)).foregroundStyle(.red)
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 20) {
                Label(session.durationString, systemImage: "clock")
                Label("\(session.confirmedEvents.count) events", systemImage: "waveform")
                let uncertain = session.events.filter { $0.isUncertain }.count
                if uncertain > 0 {
                    Label("\(uncertain) to review", systemImage: "questionmark.circle")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Session Detail

struct SessionDetailView: View {
    @EnvironmentObject var store: SessionStore
    let sessionID: UUID

    private var session: NightSession? {
        store.sessions.first { $0.id == sessionID }
    }

    var body: some View {
        Group {
            if let session {
                ScrollView {
                    VStack(spacing: 20) {
                        SummaryHeader(sessionID: sessionID)
                        EventBreakdownChart(sessionID: sessionID)
                        TimelineChart(session: session)
                        UncertainEventsTriage(sessionID: sessionID)
                        ConfirmedEventsList(sessionID: sessionID)
                    }
                    .padding()
                }
            } else {
                Text("Session not found").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Session Report")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Summary header

private struct SummaryHeader: View {
    @EnvironmentObject var store: SessionStore
    let sessionID: UUID

    private var session: NightSession? {
        store.sessions.first { $0.id == sessionID }
    }

    var body: some View {
        if let session {
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                ForEach(session.detectedClasses, id: \.self) { sc in
                    StatCard(emoji: sc.emoji, label: sc.rawValue,
                             value: "\(session.count(of: sc))", note: sc.medicalNote)
                }
                StatCard(emoji: "⏱️", label: "Duration",
                         value: session.durationString, note: nil)
                StatCard(emoji: "🌙", label: "Started",
                         value: session.startDate.formatted(.dateTime.hour().minute()), note: nil)
            }
        }
    }
}

private struct StatCard: View {
    let emoji: String
    let label: String
    let value: String
    let note: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(emoji).font(.title2)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundStyle(.secondary)
            if let note {
                Text(note).font(.caption2).foregroundStyle(.secondary).italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Charts

private struct EventBreakdownChart: View {
    @EnvironmentObject var store: SessionStore
    let sessionID: UUID

    private var session: NightSession? {
        store.sessions.first { $0.id == sessionID }
    }

    private var data: [(label: String, count: Int)] {
        guard let session else { return [] }
        return SoundClass.allCases.compactMap { sc in
            let c = session.count(of: sc)
            return c > 0 ? (sc.rawValue, c) : nil
        }
    }

    var body: some View {
        if !data.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Event Breakdown", systemImage: "chart.bar.fill").font(.headline)
                Chart(data, id: \.label) { item in
                    BarMark(x: .value("Count", item.count), y: .value("Event", item.label))
                        .foregroundStyle(Color("AccentNight")).cornerRadius(6)
                }
                .frame(height: CGFloat(max(data.count, 1)) * 44)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct TimelineChart: View {
    let session: NightSession

    private var hourlyData: [(hour: String, count: Int)] {
        let byHour = session.eventsByHour()
        guard let end = session.endDate else { return [] }
        let startHour = Calendar.current.component(.hour, from: session.startDate)
        let endHour   = Calendar.current.component(.hour, from: end)
        var hours: [Int] = []
        var h = startHour
        while h != (endHour + 1) % 24 { hours.append(h); h = (h + 1) % 24 }
        return hours.map { h in (String(format: "%02d:00", h), byHour[h]?.count ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Events per Hour", systemImage: "clock.badge.fill").font(.headline)
            if hourlyData.isEmpty {
                Text("No data").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding()
            } else {
                Chart(hourlyData, id: \.hour) { item in
                    BarMark(x: .value("Hour", item.hour), y: .value("Events", item.count))
                        .foregroundStyle(LinearGradient(
                            colors: [Color("AccentNight"), Color("AccentNight").opacity(0.5)],
                            startPoint: .top, endPoint: .bottom))
                        .cornerRadius(4)
                }
                .frame(height: 160)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Uncertain Events Triage

private struct UncertainEventsTriage: View {
    @EnvironmentObject var store: SessionStore
    let sessionID: UUID

    private var session: NightSession? {
        store.sessions.first { $0.id == sessionID }
    }

    private var uncertain: [AudioEvent] {
        session?.events.filter { $0.isUncertain } ?? []
    }

    var body: some View {
        if !uncertain.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Review These Sounds", systemImage: "questionmark.circle.fill")
                        .font(.headline).foregroundStyle(.orange)
                    Spacer()
                    Text("\(uncertain.count)")
                        .font(.caption).fontWeight(.semibold)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15)).foregroundStyle(.orange)
                        .clipShape(Capsule())
                }

                Text("Tap ▶ to listen, then ✓ to confirm or ✗ to delete.")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(uncertain) { event in
                    UncertainEventRow(event: event, sessionID: sessionID)
                }
            }
            .padding()
            .background(Color.orange.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.25), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - Uncertain Event Row
// ✓ on known class  → confirm directly
// ✓ on unknown      → open reclassify sheet
// ✗ on ALL classes  → open reclassify sheet (user can pick correct class or delete)

private struct UncertainEventRow: View {
    @EnvironmentObject var store: SessionStore
    let event: AudioEvent
    let sessionID: UUID

    @State private var player:             AVAudioPlayer?
    @State private var isPlaying           = false
    @State private var showReclassifySheet = false

    private var session: NightSession? {
        store.sessions.first { $0.id == sessionID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(event.soundClass.emoji).font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.soundClass.rawValue)
                        .font(.subheadline).fontWeight(.medium)
                    Text(event.timestamp, format: .dateTime.hour().minute().second())
                        .font(.caption).foregroundStyle(.secondary).fontDesign(.monospaced)
                }

                Spacer()

                Text("\(Int(event.confidence * 100))%")
                    .font(.caption2).fontWeight(.bold).foregroundStyle(.orange)

                // Play button
                if event.audioClipURL != nil {
                    Button(action: togglePlayback) {
                        Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(isPlaying ? .red : Color("AccentNight"))
                    }
                }

                // ✓ Always confirm directly (known or unknown)
                Button {
                    stopPlayback()
                    if let session {
                        withAnimation { store.confirm(event: event, in: session) }
                    }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.title2)
                }

                // ✗ Always open reclassify sheet — user picks correct class or deletes
                Button {
                    stopPlayback()
                    showReclassifySheet = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red.opacity(0.7)).font(.title2)
                }
            }

            Text("✓ confirm · ✗ reclassify or delete")
                .font(.caption2).foregroundStyle(.white.opacity(0.3))
                .padding(.leading, 4)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onDisappear { stopPlayback() }
        .sheet(isPresented: $showReclassifySheet) {
            if let session {
                ReclassifySheet(event: event) { chosenClass in
                    if let chosenClass {
                        store.reclassify(event: event, in: session, as: chosenClass)
                    } else {
                        store.dismiss(event: event, in: session)
                    }
                }
            }
        }
    }

    private func togglePlayback() { isPlaying ? stopPlayback() : startPlayback() }

    private func startPlayback() {
        guard let url = event.audioClipURL else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = 1.0
            player?.play()
            isPlaying = true
            let duration = player?.duration ?? 6.0
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { isPlaying = false }
        } catch {
            print("Playback error: \(error)")
        }
    }

    private func stopPlayback() {
        player?.stop(); player = nil; isPlaying = false
    }
}

// MARK: - Reclassify Sheet

private struct ReclassifySheet: View {
    let event: AudioEvent
    let onChoice: (SoundClass?) -> Void

    @Environment(\.dismiss) private var dismiss
    private let choices = SoundClass.allCases.filter { $0 != .unknown }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.title).foregroundStyle(Color("AccentNight"))
                        VStack(alignment: .leading) {
                            Text("Recorded at \(event.timestamp.formatted(.dateTime.hour().minute().second()))")
                                .font(.subheadline)
                            Text("What was this sound?")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                        ForEach(choices, id: \.self) { sc in
                            Button {
                                onChoice(sc)
                                dismiss()
                            } label: {
                                VStack(spacing: 8) {
                                    Text(sc.emoji).font(.title)
                                    Text(sc.rawValue)
                                        .font(.subheadline).fontWeight(.medium)
                                        .multilineTextAlignment(.center)
                                    Text(sc.medicalNote)
                                        .font(.caption2).foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button(role: .destructive) {
                        onChoice(nil)
                        dismiss()
                    } label: {
                        Label("Not a sleep sound — delete", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle("Classify Sound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Confirmed Events List

private struct ConfirmedEventsList: View {
    @EnvironmentObject var store: SessionStore
    let sessionID: UUID

    private var events: [AudioEvent] {
        (store.sessions.first { $0.id == sessionID })
            .map { $0.confirmedEvents.filter { !$0.isUncertain }.sorted { $0.timestamp < $1.timestamp } }
            ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("All Confirmed Events", systemImage: "list.bullet.clipboard").font(.headline)
            if events.isEmpty {
                Text("No confirmed events yet.")
                    .foregroundStyle(.secondary).font(.subheadline).padding()
            } else {
                ForEach(events) { event in
                    ConfirmedEventRow(event: event)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Confirmed Event Row

private struct ConfirmedEventRow: View {
    let event: AudioEvent

    @State private var player:   AVAudioPlayer?
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: 12) {
            Text(event.soundClass.emoji)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.soundClass.rawValue).font(.subheadline)
                Text(event.soundClass.medicalNote)
                    .font(.caption2).foregroundStyle(.secondary).italic()
            }

            Spacer()

            // Play button — shown for any event with a saved clip (sleep talking, uncertain)
            if event.audioClipURL != nil {
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(isPlaying ? .red : Color("AccentNight"))
                }
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(event.timestamp, format: .dateTime.hour().minute().second())
                    .font(.caption).fontDesign(.monospaced).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Circle()
                        .fill(event.confidence >= 0.7 ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(event.confidence >= 0.7 ? "High" : "Medium")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onDisappear { stopPlayback() }
    }

    private func togglePlayback() { isPlaying ? stopPlayback() : startPlayback() }

    private func startPlayback() {
        guard let url = event.audioClipURL else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = 1.0
            player?.play()
            isPlaying = true
            let duration = player?.duration ?? 15.0
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                isPlaying = false
            }
        } catch {
            print("Playback error: \(error)")
        }
    }

    private func stopPlayback() {
        player?.stop(); player = nil; isPlaying = false
    }
}
