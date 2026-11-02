import SwiftUI
import Translation

struct SettingsLyricsPane: View {
    @Bindable var model: HostModel
    @State private var translationSource = "ja"
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var preparingTranslation = false

    var body: some View {
        Form {
            Section {
                Toggle("Use LRCLIB when Music has no lyrics", isOn: $model.configuration.lyricsProviderEnabled)
            } footer: {
                Text(
                    "Sends the title, artist, album, and duration over HTTPS. Results are cached on Host and shared with Remotes."
                )
            }

            Section {
                TextField("Source language code", text: $translationSource)
                Button(preparingTranslation ? "Preparing language pair…" : "Prepare English translation") {
                    preparingTranslation = true
                    translationConfiguration = TranslationSession.Configuration(
                        source: Locale.Language(identifier: translationSource),
                        target: Locale.Language(identifier: "en")
                    )
                }
                .disabled(preparingTranslation)
            } header: {
                Text("English translation")
            } footer: {
                Text("macOS asks before downloading a missing language model. Translation stays in Cadenza Host.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Lyrics and Translation")
        .translationTask(translationConfiguration) { @concurrent session in
            // The framework runs prepareTranslation off the main actor, so the session stays off it too.
            do {
                try await session.prepareTranslation()
                await MainActor.run {
                    preparingTranslation = false
                    model.notify("English translation is ready.")
                }
            } catch {
                await MainActor.run {
                    preparingTranslation = false
                    model.showError("Could not prepare translation", error.localizedDescription)
                }
            }
        }
    }
}
