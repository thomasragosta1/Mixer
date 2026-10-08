import SwiftUI

/// The privacy policy, readable offline in Settings. Keep it word-for-word in
/// step with docs/privacy.html (the hosted copy App Store Connect links to):
/// update both whenever the app starts handling data differently.
enum PrivacyPolicy {
    static let lastUpdated = "8 October 2026"

    static let sections: [(title: String, body: String)] = [
        ("The short version",
         "Four-Track doesn't collect, sell or share anything about you. There are no accounts, no ads, no analytics and no tracking. Your recordings and projects stay on your iPhone unless you choose to send them somewhere."),
        ("Microphone",
         "Four-Track asks for the microphone so it can record your voice and instruments onto tracks. It only listens while you're recording (or running the latency calibration in Developer Mode). Audio is written to files on your iPhone and is never sent anywhere by the app."),
        ("What's stored, and where",
         "Your projects (audio files, track names, mixer and metronome settings) are saved in the app's own storage on your iPhone. App preferences, like Developer Mode and which tips you've seen, are saved there too. Deleting a project moves it to Recently Deleted until you delete it for good; deleting the app removes everything. Your device's own backups (iCloud Backup or a computer) may include this data, under Apple's terms and your settings."),
        ("Sharing and importing",
         "When you export or share a mix or a track, the app hands the file to the iOS share sheet, and it goes only where you send it. When you import a recording (from Voice Memos, Files or anywhere else), the app makes its own copy for the project and deletes the temporary copy it was given."),
        ("Network",
         "Four-Track doesn't connect to the internet. It has no servers and uses no third-party services or SDKs that collect data."),
        ("Lock screen",
         "While a song plays, the project name and playhead appear in the iOS lock screen and Control Center player so you can pause and play. That stays on your device."),
        ("Children",
         "Four-Track doesn't collect personal information from anyone, including children."),
        ("Changes",
         "If the app ever starts handling data differently, this policy will be updated before that version is released, and the date above will change."),
        ("Contact",
         "Questions about privacy: open an issue at github.com/thomasragosta1/mixer/issues, or use the App Support link on Four-Track's App Store page."),
    ]
}

struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section {
                Text("Last updated \(PrivacyPolicy.lastUpdated)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(PrivacyPolicy.sections, id: \.title) { section in
                Section(section.title) {
                    Text(section.body)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
