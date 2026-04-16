import Foundation
import AVFoundation
import SoundAnalysis
import Accelerate
import Combine

// MARK: - Classifier Output

struct ClassifierResult {
    let soundClass: SoundClass
    let confidence: Double
}

// MARK: - AudioClassifier

final class AudioClassifier: NSObject, ObservableObject {

    @Published var latestResult: ClassifierResult?
    var onDetection: ((ClassifierResult, String?) -> Void)?

    private var audioEngine      = AVAudioEngine()
    private var streamAnalyzer:  SNAudioStreamAnalyzer?
    private let analysisQueue    = DispatchQueue(label: "com.nightlogger.analysis")

    // Rolling buffer — 15 seconds for sleep talking clips
    private let bufferDuration: Double = 15.0
    private var rollingBuffer:  [Float] = []
    private var rollingFormat:  AVAudioFormat?
    private var bufferLock      = NSLock()

    // Background keep-alive
    private var silentPlayer: AVAudioPlayer?

    // Confirmed identifiers from SNClassifySoundRequest v1
    private let labelMap: [String: SoundClass] = [
        "cough":      .cough,
        "snoring":    .snore,
        "sneeze":     .sneeze,
        "speech":     .talking,
        "whispering": .talking,
        "gasp":       .gasp,
    ]

    // MARK: - Public API

    func startListening() throws {
        try configureAudioSession()
        try setupEngine()
        startSilentPlayer()
        registerNotifications()
    }

    func stopListening() {
        silentPlayer?.stop()
        silentPlayer = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        streamAnalyzer = nil
        bufferLock.lock()
        rollingBuffer.removeAll()
        bufferLock.unlock()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Audio Session

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker]
        )
        try session.setActive(true)
    }

    // MARK: - Silent Player
    // iOS only keeps a .playAndRecord session alive in background
    // if the app is actively playing audio. Silent loop satisfies this.

    private func startSilentPlayer() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let frames = AVAudioFrameCount(44100)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: frames) else { return }
        buffer.frameLength = frames

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nightlogger_silence.wav")
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            silentPlayer = try AVAudioPlayer(contentsOf: url)
            silentPlayer?.numberOfLoops = -1
            silentPlayer?.volume        = 0.0
            silentPlayer?.prepareToPlay()
            silentPlayer?.play()
            print("AudioClassifier: silent player — \(silentPlayer?.isPlaying ?? false)")
        } catch {
            print("AudioClassifier: silent player error – \(error)")
        }
    }

    // MARK: - Engine Setup

    private func setupEngine() throws {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = AVAudioEngine()

        let inputNode   = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        rollingFormat   = inputFormat

        // Active output path — iOS needs this for background recording
        let mixer = audioEngine.mainMixerNode
        audioEngine.connect(inputNode, to: mixer, format: inputFormat)
        mixer.outputVolume = 0.0

        streamAnalyzer = SNAudioStreamAnalyzer(format: inputFormat)

        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)

        // ── Log all available identifiers (remove after verification) ──
        request.knownClassifications.forEach { print("IDENTIFIER: \($0)") }
        // ──────────────────────────────────────────────────────────────

        request.windowDuration = CMTimeMakeWithSeconds(1.0, preferredTimescale: 44_100)
        request.overlapFactor  = 0.5
        try streamAnalyzer?.add(request, withObserver: self)

        let maxSamples = Int(inputFormat.sampleRate * bufferDuration)

        inputNode.installTap(onBus: 0,
                             bufferSize: 8192,
                             format: inputFormat) { [weak self] buffer, time in
            guard let self else { return }

            self.analysisQueue.async {
                self.streamAnalyzer?.analyze(buffer,
                                             atAudioFramePosition: time.sampleTime)
            }

            if let channelData = buffer.floatChannelData?[0] {
                let samples = Array(UnsafeBufferPointer(start: channelData,
                                                        count: Int(buffer.frameLength)))
                self.bufferLock.lock()
                self.rollingBuffer.append(contentsOf: samples)
                if self.rollingBuffer.count > maxSamples {
                    self.rollingBuffer.removeFirst(self.rollingBuffer.count - maxSamples)
                }
                self.bufferLock.unlock()
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        print("AudioClassifier: engine started")
    }

    // MARK: - Notifications

    private func registerNotifications() {
        let session = AVAudioSession.sharedInstance()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: session)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification, object: session)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification, object: session)
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }
        if type == .ended {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                try? AVAudioSession.sharedInstance().setActive(true)
                self?.silentPlayer?.play()
                try? self?.audioEngine.start()
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }
        if reason == .oldDeviceUnavailable {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                try? self?.audioEngine.start()
            }
        }
    }

    @objc private func handleMediaServicesReset() {
        print("AudioClassifier: media services reset — restarting")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            try? self.configureAudioSession()
            try? self.setupEngine()
            self.startSilentPlayer()
        }
    }

    // MARK: - Clip Saving

    private func saveClip(eventID: UUID) -> String? {
        guard let format = rollingFormat else { return nil }

        bufferLock.lock()
        let samples = rollingBuffer
        bufferLock.unlock()

        guard !samples.isEmpty else { return nil }

        let docs    = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = docs.appendingPathComponent("clip_\(eventID.uuidString).wav")

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        if let channelData = buffer.floatChannelData?[0] {
            let gain: Float = 6.0
            for (i, sample) in samples.enumerated() {
                channelData[i] = max(-1.0, min(1.0, sample * gain))
            }
        }

        do {
            let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
            try file.write(from: buffer)
            return fileURL.path
        } catch {
            print("AudioClassifier: clip save error – \(error)")
            return nil
        }
    }
}

// MARK: - SNResultsObserving

extension AudioClassifier: SNResultsObserving {

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult else { return }

        for classification in classificationResult.classifications {
            guard let soundClass = labelMap[classification.identifier] else { continue }
            let confidence = classification.confidence
            guard confidence >= 0.45 else { continue }

            let result = ClassifierResult(soundClass: soundClass, confidence: confidence)

            if confidence >= 0.70 {
                if soundClass == .talking {
                    // Sleep talking — always save clip so user can listen back
                    let clipPath = saveClip(eventID: UUID())
                    DispatchQueue.main.async { [weak self] in
                        self?.latestResult = result
                        self?.onDetection?(result, clipPath)
                    }
                } else {
                    // High confidence — no clip needed
                    DispatchQueue.main.async { [weak self] in
                        self?.latestResult = result
                        self?.onDetection?(result, nil)
                    }
                }
            } else {
                // Medium confidence — save clip for morning review
                let clipPath = saveClip(eventID: UUID())
                DispatchQueue.main.async { [weak self] in
                    self?.latestResult = result
                    self?.onDetection?(result, clipPath)
                }
            }
            return
        }

        // Unknown fallback — something loud was detected but not in our map
        if let top = classificationResult.classifications.first,
           top.confidence >= 0.70 {
            let result   = ClassifierResult(soundClass: .unknown, confidence: 0.50)
            let clipPath = saveClip(eventID: UUID())
            DispatchQueue.main.async { [weak self] in
                self?.latestResult = result
                self?.onDetection?(result, clipPath)
            }
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("AudioClassifier: SoundAnalysis error – \(error)")
    }

    func requestDidComplete(_ request: SNRequest) {}
}
