//
//  LiveTranslationView.swift
//  notchprompt
//
//  Displays live-translated text inside the overlay when translation
//  mode is active. Also bridges the Translation framework session via
//  the `.translationTask` modifier.
//

import SwiftUI
import Translation

struct LiveTranslationOverlayContent: View {
    @ObservedObject var model: PrompterModel
    @ObservedObject var translationManager: LiveTranslationManager

    @State private var translationConfig: TranslationSession.Configuration?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !translationManager.translatedText.isEmpty {
                Text(translationManager.translatedText)
                    .font(.system(size: CGFloat(model.fontSize), weight: .regular, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !translationManager.recognizedText.isEmpty {
                Text(translationManager.recognizedText)
                    .font(.system(size: CGFloat(model.fontSize), weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(translationManager.isListening ? "Listening for speech…" : "Translation ready")
                        .font(.system(size: max(model.fontSize * 0.72, 13), weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                    if !translationManager.detectedLanguage.isEmpty {
                        Text("Detected: \(displayName(for: translationManager.detectedLanguage))")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .translationTask(translationConfig) { session in
            translationManager.handleTranslationSession(session)
        }
        .onAppear {
            updateTranslationConfig()
        }
        .onChange(of: translationManager.detectedLanguage) { _, _ in
            updateTranslationConfig()
        }
        .onChange(of: model.targetLanguageCode) { _, newValue in
            translationManager.targetLanguageCode = newValue
            updateTranslationConfig()
        }
    }

    private func updateTranslationConfig() {
        translationConfig = translationManager.makeTranslationConfiguration()
    }

    private func displayName(for code: String) -> String {
        let locale = Locale.current
        return locale.localizedString(forIdentifier: code) ?? code
    }
}

struct LiveTranslationSettingsView: View {
    @ObservedObject var model: PrompterModel
    @ObservedObject var translationManager: LiveTranslationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Target language")
                    .frame(width: 164, alignment: .leading)
                Picker("", selection: $model.targetLanguageCode) {
                    ForEach(LiveTranslationManager.supportedLanguages) { lang in
                        Text(lang.displayName).tag(lang.code)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: model.targetLanguageCode) { _, newValue in
                    translationManager.targetLanguageCode = newValue
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                Button(action: {
                    model.isLiveTranslationMode.toggle()
                    if model.isLiveTranslationMode {
                        translationManager.targetLanguageCode = model.targetLanguageCode
                        translationManager.startListening()
                    } else {
                        translationManager.stopListening()
                    }
                }) {
                    Label(
                        model.isLiveTranslationMode ? "Stop Translation" : "Start Translation",
                        systemImage: model.isLiveTranslationMode ? "stop.circle.fill" : "play.circle.fill"
                    )
                }
                .controlSize(.regular)

                Text(translationManager.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            if !translationManager.detectedLanguage.isEmpty {
                HStack {
                    Text("Detected language")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(displayName(for: translationManager.detectedLanguage))
                        .font(.footnote.weight(.medium))
                    Spacer()
                }
            }

            if let error = translationManager.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Uses your microphone to capture speech, auto-detect the spoken language, and translate it live to the selected target language. The translated text appears in the overlay.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func displayName(for code: String) -> String {
        let locale = Locale.current
        return locale.localizedString(forIdentifier: code) ?? code
    }
}
