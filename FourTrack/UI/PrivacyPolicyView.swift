import SwiftUI

/// The privacy policy, readable offline in Settings. Keep it word-for-word in
/// step with docs/privacy.html (the hosted copy App Store Connect links to):
/// update both whenever the app starts handling data differently.
enum PrivacyPolicy {
    static let lastUpdated = "16 October 2026"

    static let sections: [(title: String, body: String)] = [
        ("The short version",
         "Four-Track doesn't collect, sell or share anything about you. There are no accounts, no ads, no analytics and no tracking. Your recordings and projects stay on your iPhone, and in your own iCloud if you turn on iCloud sync. The developer can't see them either way."),
        ("Microphone",
         "Four-Track asks for the microphone so it can record your voice and instruments onto tracks. It only listens while you're recording (or running the latency calibration in Developer Mode). Audio is written to files on your iPhone. It only leaves the device if you share it, or if you turn on iCloud sync (your own iCloud)."),
        ("What's stored, and where",
         "Your projects (audio files, track names, mixer and metronome settings) are saved in the app's own storage on your iPhone. App preferences, like Developer Mode and which tips you've seen, are saved there too. Deleting a project moves it to Recently Deleted until you delete it for good; deleting the app removes everything. Your device's own backups (iCloud Backup or a computer) may include this data, under Apple's terms and your settings."),
        ("iCloud sync",
         "iCloud sync is off until you turn it on in Settings. When it's on, your projects (audio, track names and settings) are stored in your own iCloud account using Apple's CloudKit private database, so they appear on your other devices signed in to the same Apple Account. Only you can access that data: the developer can't see, read or delete it, and it's handled under Apple's iCloud terms and privacy policy. It counts toward your iCloud storage. Turning sync off stops sending anything; to remove the copies in iCloud, use Settings → [your name] → iCloud → Manage Storage on your iPhone."),
        ("Sharing and importing",
         "When you export or share a mix or a track, the app hands the file to the iOS share sheet, and it goes only where you send it. When you import a recording (from Voice Memos, Files or anywhere else), the app makes its own copy for the project and deletes the temporary copy it was given."),
        ("Network",
         "Four-Track has no servers of its own and uses no third-party services or SDKs. The only time it uses the internet is for iCloud sync, if you turn it on, which talks only to Apple's iCloud."),
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
