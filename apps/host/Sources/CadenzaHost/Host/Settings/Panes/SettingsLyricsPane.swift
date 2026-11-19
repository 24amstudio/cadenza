import SwiftUI
import Translation

struct SettingsLyricsPane: View {
    @Bindable var model: HostModel
    @State private var translationSource = "ja"
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var preparingTranslation = false
    @State private var translationStatus: String?

    var body: some View {
        Form {
            RestartHostSection(model: model, settings: [.lyrics])
            Section {
                Toggle("Find lyrics online when Music has none", isOn: model.committedBinding(\.lyricsProviderEnabled))
            } footer: {
                Text(
                    "Sends the song's title, artist, album, and duration to LRCLIB over HTTPS. Results are cached on this Mac and shared with Remotes."
                )
            }

            Section {
                Picker("Translate from", selection: $translationSource) {
                    ForEach(translationLanguages) { language in
                        Text(language.name).tag(language.code)
                    }
                }
                Button("Download Translation Language", action: prepareTranslation)
                    .disabled(preparingTranslation)
                translationStatusLine
            } header: {
                Text("English translation")
            } footer: {
                Text("macOS asks before downloading a missing language model. Translation happens on this Mac.")
            }
        }
        .formStyle(.grouped)
        .translationTask(translationConfiguration) { @concurrent session in
            // The framework runs prepareTranslation off the main actor, so the session stays off it too.
            do {
                try await session.prepareTranslation()
                await MainActor.run {
                    preparingTranslation = false
                    translationStatus = "English translation is ready."
                }
            } catch {
                await MainActor.run {
                    preparingTranslation = false
                    translationStatus = "This language could not be prepared."
                    model.showError("Could not prepare translation", error.localizedDescription)
                }
            }
        }
    }

    @ViewBuilder private var translationStatusLine: some View {
        if preparingTranslation {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Preparing translation…")
            }
            .foregroundStyle(.secondary)
        } else if let translationStatus {
            Text(translationStatus)
                .foregroundStyle(.secondary)
        }
    }

    private func prepareTranslation() {
        preparingTranslation = true
        translationStatus = nil
        let configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: translationSource),
            target: Locale.Language(identifier: "en")
        )
        // An equal configuration does not rerun the task, so the same language is invalidated to run again.
        if configuration == translationConfiguration { translationConfiguration?.invalidate() }
        translationConfiguration = configuration
    }

    private var translationLanguages: [TranslationLanguage] {
        Self.translationLanguageCodes
            .map { code in
                TranslationLanguage(
                    code: code,
                    name: Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code)
            }
            .sorted { $0.name < $1.name }
    }

    private static let translationLanguageCodes = [
        "ja", "ko", "zh", "es", "fr", "de", "pt", "it", "ru", "ar", "hi", "id", "th", "vi", "tr",
    ]

    private struct TranslationLanguage: Identifiable {
        let code: String
        let name: String
        var id: String { code }
    }
}
