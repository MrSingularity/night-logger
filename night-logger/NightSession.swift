import Foundation
import Combine

// MARK: - Audio Event

enum ConfidenceLevel: String, Codable {
    case high
    case medium
    case low
}

enum SoundClass: String, Codable, CaseIterable {
    case cough   = "Cough"
    case snore   = "Snoring"
    case sneeze  = "Sneeze"
    case talking = "Sleep talking"
    case gasp    = "Gasping"
    case unknown = "Unknown sound"

    var emoji: String {
        switch self {
        case .cough:   return "😮‍💨"
        case .snore:   return "😴"
        case .sneeze:  return "🤧"
        case .talking: return "💬"
        case .gasp:    return "😮"
        case .unknown: return "❓"
        }
    }

    var medicalNote: String {
        switch self {
        case .cough:   return "May indicate airway irritation"
        case .snore:   return "Associated with sleep apnea"
        case .sneeze:  return "Possible allergen response"
        case .talking: return "Sleep talking detected"
        case .gasp:    return "Possible apnea event — review carefully"
        case .unknown: return "Unidentified sound"
        }
    }

    var priority: Int {
        switch self {
        case .gasp:    return 5
        case .cough:   return 3
        case .snore:   return 3
        case .talking: return 2
        case .sneeze:  return 1
        case .unknown: return 0
        }
    }
}

// MARK: - Audio Event

struct AudioEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let soundClass: SoundClass
    let confidence: Double
    var isDismissed: Bool
    var isConfirmed: Bool

    /// Local file path to a ~5s audio clip (only saved for medium-confidence events)
    var audioClipPath: String?

    var audioClipURL: URL? {
        guard let path = audioClipPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    var confidenceLevel: ConfidenceLevel {
        switch confidence {
        case 0.70...: return .high
        case 0.45...: return .medium
        default:      return .low
        }
    }

    var isUncertain: Bool { confidenceLevel == .medium && !isConfirmed && !isDismissed }

    init(timestamp: Date, soundClass: SoundClass, confidence: Double, audioClipPath: String? = nil) {
        self.id            = UUID()
        self.timestamp     = timestamp
        self.soundClass    = soundClass
        self.confidence    = confidence
        self.isDismissed   = false
        self.isConfirmed   = false
        self.audioClipPath = audioClipPath
    }
}

// MARK: - Night Session

struct NightSession: Identifiable, Codable, Hashable, Equatable {
    let id: UUID
    let startDate: Date
    var endDate: Date?
    var events: [AudioEvent]

    init(startDate: Date = .now) {
        self.id        = UUID()
        self.startDate = startDate
        self.events    = []
    }

    var confirmedEvents: [AudioEvent] {
        events.filter { !$0.isDismissed }
    }

    func eventsByHour() -> [Int: [AudioEvent]] {
        Dictionary(grouping: confirmedEvents) { event in
            Calendar.current.component(.hour, from: event.timestamp)
        }
    }

    func count(of soundClass: SoundClass) -> Int {
        confirmedEvents.filter { $0.soundClass == soundClass }.count
    }

    var durationString: String {
        guard let end = endDate else { return "Ongoing" }
        let interval = end.timeIntervalSince(startDate)
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        return "\(h)h \(m)m"
    }

    var detectedClasses: [SoundClass] {
        let present = Set(confirmedEvents.map { $0.soundClass })
        return SoundClass.allCases
            .filter { present.contains($0) }
            .sorted { $0.priority > $1.priority }
    }

    static func == (lhs: NightSession, rhs: NightSession) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Session Store

final class SessionStore: ObservableObject {
    @Published var sessions: [NightSession] = []
    @Published var activeSession: NightSession?

    private let saveURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("nightlogger_sessions.json")
    }()

    init() { load() }

    func startSession() {
        activeSession = NightSession(startDate: .now)
        objectWillChange.send()
    }

    func appendEvent(_ event: AudioEvent) {
        guard activeSession != nil else { return }
        activeSession!.events.append(event)
        objectWillChange.send()
    }

    func stopSession() {
        guard var session = activeSession else { return }
        session.endDate = .now
        sessions.insert(session, at: 0)
        activeSession = nil
        save()
    }

    func dismiss(event: AudioEvent, in session: NightSession) {
        // Also delete the audio clip file to save storage
        if let url = event.audioClipURL {
            try? FileManager.default.removeItem(at: url)
        }
        mutate(eventID: event.id, sessionID: session.id) { $0.isDismissed = true }
    }

    func confirm(event: AudioEvent, in session: NightSession) {
        mutate(eventID: event.id, sessionID: session.id) { $0.isConfirmed = true }
    }

    /// Reclassify an unknown (or misclassified) event as a different sound class
    func reclassify(event: AudioEvent, in session: NightSession, as newClass: SoundClass) {
        mutate(eventID: event.id, sessionID: session.id) {
            $0 = AudioEvent(
                timestamp:     $0.timestamp,
                soundClass:    newClass,
                confidence:    0.70,          // treat as confirmed high-confidence
                audioClipPath: $0.audioClipPath
            )
            $0.isConfirmed = true
        }
    }

    func deleteSession(_ session: NightSession) {
        // Clean up all audio clips for this session
        for event in session.events {
            if let url = event.audioClipURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        sessions.removeAll { $0.id == session.id }
        save()
    }

    private func mutate(eventID: UUID, sessionID: UUID, update: (inout AudioEvent) -> Void) {
        guard let si = sessions.firstIndex(where: { $0.id == sessionID }),
              let ei = sessions[si].events.firstIndex(where: { $0.id == eventID })
        else { return }
        update(&sessions[si].events[ei])
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            print("NightLogger: save error – \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL) else { return }
        sessions = (try? JSONDecoder().decode([NightSession].self, from: data)) ?? []
    }
}
