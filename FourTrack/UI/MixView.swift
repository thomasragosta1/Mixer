import SwiftUI
import FourTrackCore

/// Mix mode: four vertical channel strips side by side (plus a small master
/// strip in Developer Mode). Scrolls vertically when the screen is short.
struct MixView: View {
    @Bindable var model: ProjectViewModel
    @State private var detailTrack: Int?

    var body: some View {
        GeometryReader { geo in
            let columns = model.visibleTrackCount + (model.developerMode ? 1 : 0)
            let spacing: CGFloat = 6
            let width = min(120, (geo.size.width - 16 - spacing * CGFloat(columns - 1)) / CGFloat(columns))
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(model.visibleLanes, id: \.self) { i in
                        ChannelStripView(model: model, index: i) {
                            detailTrack = i
                        }
                        .frame(width: width)
                    }
                    if model.developerMode {
                        MasterStripView(model: model)
                            .frame(width: width)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(item: Binding(
            get: { detailTrack.map(TrackID.init) },
            set: { detailTrack = $0?.id }
        )) { item in
            DevTrackControlsView(model: model, index: item.id)
        }
    }

    private struct TrackID: Identifiable {
        let id: Int
    }
}

/// Small master strip (Developer Mode): master volume and meter.
struct MasterStripView: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        VStack(spacing: 10) {
            Text("Master")
                .font(.caption.weight(.semibold))
                .frame(height: 28)
            Spacer(minLength: 0)
            StripLabel(title: "Volume", value: SliderSpeech.shortDB(MacroCurves.volumeDB(model.project.masterVolume)))
            HStack(spacing: 4) {
                VolumeFader(label: "Master volume", value: Binding(
                    get: { model.project.masterVolume },
                    set: { model.setMasterVolume($0) }
                ), axis: .vertical)
                MeterView(level: model.meterLevels[MeterStore.masterIndex]) {
                    model.resetClip(MeterStore.masterIndex)
                }
            }
            .frame(height: ChannelStripView.faderHeight)
        }
        .padding(.vertical, 8)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
    }
}

/// Caption above each strip control: name and current value.
struct StripLabel: View {
    let title: String
    let value: String
    var isCustom = false

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(isCustom ? "Custom" : value)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(isCustom ? Color.accentColor : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityHidden(true)
    }
}
