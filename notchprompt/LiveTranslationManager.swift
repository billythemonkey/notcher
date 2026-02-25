//
//  LiveTranslationManager.swift
//  notchprompt
//
//  Live speech recognition and translation engine.
//  Captures microphone audio via AVAudioEngine, transcribes with
//  SFSpeechRecognizer (auto-detecting the source language), and
//  translates results using Apple's Translation framework.
//

import AVFoundation
import Combine
import Foundation
import NaturalLanguage
import Speech
import Translation

@MainActor
final class LiveTranslationManager: ObservableObject {
    static let shared = LiveTranslationManager()

    // MARK: - Published state

    @Published private(set) var isListening = false
    @Published private(set) var recognizedText = ""
    @Published private(set) var translatedText = ""
    @Published private(set) var detectedLanguage = ""
    @Published private(set) var statusMessage = "Idle"
    @Published private(set) var errorMessage: String?

    @Published var targetLanguageCode: String = "pt-PT" {
        didSet { translationSession = nil }
    }

    // MARK: - Supported target languages

    struct SupportedLanguage: Identifiable, Hashable {
        let code: String
        let displayName: String
        var id: String { code }
    }

    static let supportedLanguages: [SupportedLanguage] = [
        .init(code: "pt-PT", displayName: "Portuguese (Portugal)"),
        .init(code: "pt-BR", displayName: "Portuguese (Brazil)"),
        .init(code: "es", displayName: "Spanish"),
        .init(code: "fr", displayName: "French"),
        .init(code: "de", displayName: "German"),
        .init(code: "it", displayName: "Italian"),
        .init(code: "ja", displayName: "Japanese"),
        .init(code: "ko", displayName: "Korean"),
        .init(code: "zh-Hans", displayName: "Chinese (Simplified)"),
        .init(code: "zh-Hant", displayName: "Chinese (Traditional)"),
        .init(code: "ar", displayName: "Arabic"),
        .init(code: "ru", displayName: "Russian"),
        .init(code: "hi", displayName: "Hindi"),
        .init(code: "pl", displayName: "Polish"),
        .init(code: "nl", displayName: "Dutch"),
        .init(code: "tr", displayName: "Turkish"),
        .init(code: "uk", displayName: "Ukrainian"),
        .init(code: "th", displayName: "Thai"),
        .init(code: "vi", displayName: "Vietnamese"),
        .init(code: "en", displayName: "English"),
    ]

    // MARK: - Private

    private lazy var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private let languageRecognizer = NLLanguageRecognizer()
    private var translationSession: TranslationSession?
    private var translationConfiguration: TranslationSession.Configuration?
    private var pendingTranslationTask: Task<Void, Never>?

    private init() {}

    // MARK: - Public API

    func startListening() {
        guard !isListening else { return }
        errorMessage = nil

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .authorized:
                    self.beginRecognition()
                case .denied:
                    self.errorMessage = "Speech recognition permission denied. Enable it in System Settings → Privacy & Security → Speech Recognition."
                    self.statusMessage = "Permission denied"
                case .restricted:
                    self.errorMessage = "Speech recognition is restricted on this device."
                    self.statusMessage = "Restricted"
                case .notDetermined:
                    self.errorMessage = "Speech recognition permission not yet determined."
                    self.statusMessage = "Not authorized"
                @unknown default:
                    self.errorMessage = "Unknown speech recognition authorization status."
                    self.statusMessage = "Error"
                }
            }
        }
    }

    func stopListening() {
        pendingTranslationTask?.cancel()
        pendingTranslationTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        translationSession = nil
        isListening = false
        statusMessage = "Stopped"
    }

    // MARK: - Translation Configuration

    /// Returns a `TranslationSession.Configuration` for the current detected-source → target pair.
    func makeTranslationConfiguration() -> TranslationSession.Configuration? {
        let targetLocale = Locale.Language(identifier: targetLanguageCode)

        if detectedLanguage.isEmpty {
            // Source auto-detected – let the framework figure it out
            return TranslationSession.Configuration(target: targetLocale)
        }

        let sourceLocale = Locale.Language(identifier: detectedLanguage)
        // Don't translate when source == target
        guard sourceLocale.minimalIdentifier != targetLocale.minimalIdentifier else { return nil }
        return TranslationSession.Configuration(source: sourceLocale, target: targetLocale)
    }

    /// Called from SwiftUI `.translationTask` to provide a session for translation.
    func handleTranslationSession(_ session: TranslationSession) {
        translationSession = session
        // If we already have text queued, translate it now.
        if !recognizedText.isEmpty {
            translateLatest()
        }
    }

    // MARK: - Private: Speech Recognition

    private func beginRecognition() {
        // Use a recognizer that supports on-device recognition for best
        // latency and privacy. Passing `nil` uses the system default locale,
        // which handles auto-detection of the spoken language.
        speechRecognizer = SFSpeechRecognizer()
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognizer is unavailable."
            statusMessage = "Unavailable"
            return
        }

        do {
            try startAudioEngine()
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            statusMessage = "Audio error"
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        // Prefer on-device to reduce latency
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.recognizedText = result.bestTranscription.formattedString
                    self.detectLanguage(from: self.recognizedText)
                    self.translateLatest()
                }

                if let error {
                    // Recognition ended (could be timeout or real error)
                    let nsError = error as NSError
                    // Code 1 = recognition was cancelled by us
                    // Code 216 = "kAFAssistantErrorDomain" (recognition timed out)
                    if nsError.code != 1 {
                        #if DEBUG
                        print("[LiveTranslation] Recognition error: \(error)")
                        #endif
                        // Auto-restart on timeout
                        if self.isListening {
                            self.restartRecognition()
                        }
                    }
                }

                if result?.isFinal == true, self.isListening {
                    self.restartRecognition()
                }
            }
        }

        isListening = true
        statusMessage = "Listening…"
    }

    private func restartRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        // Brief delay before restarting to avoid rapid cycling
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard self.isListening else { return }
            self.beginRecognition()
        }
    }

    private func startAudioEngine() throws {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw NSError(
                domain: "LiveTranslation",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No audio input available. Check your microphone."]
            )
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    // MARK: - Private: Language Detection

    private func detectLanguage(from text: String) {
        guard !text.isEmpty else { return }
        languageRecognizer.reset()
        languageRecognizer.processString(text)
        if let dominant = languageRecognizer.dominantLanguage {
            detectedLanguage = dominant.rawValue
        }
    }

    // MARK: - Private: Translation

    private func translateLatest() {
        guard let session = translationSession else { return }
        let textToTranslate = recognizedText
        guard !textToTranslate.isEmpty else { return }

        pendingTranslationTask?.cancel()
        pendingTranslationTask = Task { @MainActor in
            do {
                let response = try await session.translate(textToTranslate)
                guard !Task.isCancelled else { return }
                self.translatedText = response.targetText
                self.statusMessage = "Translating…"
            } catch {
                guard !Task.isCancelled else { return }
                #if DEBUG
                print("[LiveTranslation] Translation error: \(error)")
                #endif
                self.statusMessage = "Translation error"
            }
        }
    }
}
