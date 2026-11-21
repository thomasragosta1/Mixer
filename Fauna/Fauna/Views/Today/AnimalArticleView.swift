import SwiftUI

/// The full reading experience for one animal: stretchy photo header, condensed article,
/// facts, range map, Red List status, ways to help, and (on Today) the quiz to unlock another.
struct AnimalArticleView: View {
    enum Mode { case today, journal }

    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    let animal: Animal
    var mode: Mode = .today
    /// Starts the unlock quiz; Today supplies it so the quiz outlives this view when the next animal arrives.
    var onStartQuiz: (() -> Void)? = nil
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 44
    /// True once the photo has scrolled away, to fade in a frosted bar behind the status bar.
    @State private var pastHero = false

    private let heroHeight: CGFloat = 520
    private var accent: Color { animal.group.color }

    var body: some View {
        ZStack(alignment: .top) {
            article
                .background(Color(.systemBackground))
                .ignoresSafeArea(edges: .top)
            // Pinned to the top of the safe area; its material extends up under the status bar.
            Text(animal.name)
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, 64)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(.bar)
                .overlay(alignment: .bottom) { Divider() }
                .opacity(pastHero ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .scrollIndicators(.hidden)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(pastHero ? nil : .dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: animal.wikipediaURL,
                          subject: Text(animal.name),
                          message: Text("I met the \(animal.name) on Fauna today. \(animal.tagline).")) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(pastHero ? Color.primary : .white)
                        .frame(width: 36, height: 36)
                        .background(pastHero ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Material.ultraThinMaterial), in: Circle())
                }
                .accessibilityLabel("Share")
            }
        }
    }

    private var article: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    content
                        .background(
                            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.12), radius: 20, y: -6)
                        )
                        .padding(.top, -30)
                }
            }
            .task { await scrollForScreenshot(proxy) }
        }
    }

    /// `-FaunaScrollTo <section>` scrolls on launch, for App Store screenshots.
    private func scrollForScreenshot(_ proxy: ScrollViewProxy) async {
        let args = ProcessInfo.processInfo.arguments
        guard mode == .today, let i = args.firstIndex(of: "-FaunaScrollTo"), i + 1 < args.count else { return }
        try? await Task.sleep(for: .seconds(1.5))
        proxy.scrollTo(args[i + 1], anchor: .top)
    }

    // MARK: Hero

    private var hero: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .scrollView).minY
            let stretch = max(0, minY)
            let parallax = minY < 0 ? -minY * 0.35 : 0
            ZStack(alignment: .bottomLeading) {

                AnimalPhoto(animal: animal, size: .hero)
                    .frame(width: geo.size.width, height: heroHeight + stretch)
                    .offset(y: parallax)

                LinearGradient(stops: [
                    .init(color: .black.opacity(0.35), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .clear, location: 0.45),
                    .init(color: .black.opacity(0.78), location: 1),
                ], startPoint: .top, endPoint: .bottom)

                heroTitle
                    .padding(.horizontal, 24)
                    .padding(.bottom, 58)
                    .offset(y: parallax * 0.4)
                    .opacity(minY < 0 ? Double(max(0, 1 + minY / 320)) : 1)
            }
            .frame(width: geo.size.width, height: heroHeight + stretch)
            .clipped()
            .offset(y: -stretch)
        }
        .frame(height: heroHeight)
        .onGeometryChange(for: Bool.self) { geo in
            geo.frame(in: .scrollView).minY < -(heroHeight - 140)
        } action: { past in
            withAnimation(.easeInOut(duration: 0.25)) { pastHero = past }
        }
    }

    private var heroTitle: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrowText.uppercased())
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(animal.name)
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            Text(animal.scientificName)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 8) {
                GroupPill(group: animal.group)
                StatusPill(status: animal.status, onDark: true)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eyebrowText: String {
        switch mode {
        case .today:
            let index = store.state.todayChain.firstIndex(of: animal.id) ?? 0
            let date = Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            return index == 0 ? "Today · \(date)" : "Bonus animal · \(date)"
        case .journal:
            if let entry = store.state.journal.first(where: { $0.animalID == animal.id }) {
                return "Met " + entry.date.formatted(.dateTime.month(.wide).day().year())
            }
            return "From your journal"
        }
    }

    // MARK: Article

    private var content: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "book.pages")
                    Text("\(animal.readingMinutes) min read · Condensed from Wikipedia")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

                Text(animal.tagline)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)

                Text(animal.lede)
                    .font(FaunaFont.lede)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FactGrid(facts: animal.facts, tint: accent)
                .id("facts")

            ArticleSection(title: "Where it lives", symbol: "map.fill", tint: accent) {
                VStack(alignment: .leading, spacing: 16) {
                    RangeMap(animal: animal)
                        .frame(height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            Label(animal.range, systemImage: "location.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .environment(\.colorScheme, .dark)
                                .padding(10)
                        }
                    Paragraph(animal.home)
                    FlowLayout(spacing: 6) {
                        ForEach(animal.regions) { region in
                            Label(region.title, systemImage: region.symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(accent.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }

            ArticleSection(title: "How it lives", symbol: "leaf.fill", tint: accent) {
                Paragraph(animal.life)
            }

            ArticleSection(title: "What makes it remarkable", symbol: "sparkles", tint: accent) {
                Paragraph(animal.remarkable)
            }

            DidYouKnowCard(text: animal.didYouKnow, tint: accent)
                .id("didYouKnow")

            ArticleSection(title: "Its future", symbol: "heart.fill", tint: accent) {
                VStack(alignment: .leading, spacing: 20) {
                    ConservationScale(status: animal.status)
                        .padding(16)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Paragraph(animal.outlook)
                }
            }

            HelpSection(animal: animal)
                .id("help")

            sourceFooter

            if mode == .today, let onStartQuiz {
                UnlockCard(animal: animal, start: onStartQuiz)
                    .id("unlock")
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .padding(.bottom, 48)
    }

    private var sourceFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Button {
                openURL(animal.wikipediaURL)
            } label: {
                HStack {
                    Image(systemName: "w.circle.fill")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Read the full article on Wikipedia")
                            .font(.subheadline.weight(.semibold))
                        Text("Text condensed from Wikipedia (CC BY-SA 4.0). Photo from Wikimedia Commons.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(PressableStyle())
        }
    }
}

// MARK: - Pieces

private struct Paragraph: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(FaunaFont.body)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ArticleSection<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.title3.bold())
                .labelStyle(SectionLabelStyle(tint: tint))
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

private struct SectionLabelStyle: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .foregroundStyle(tint)
                .imageScale(.medium)
            configuration.title
        }
    }
}

struct FactGrid: View {
    let facts: [Fact]
    let tint: Color

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(facts, id: \.self) { fact in
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: fact.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fact.value)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(fact.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(fact.label): \(fact.value)")
            }
        }
    }
}

private struct DidYouKnowCard: View {
    let text: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Did You Know?", systemImage: "lightbulb.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Foundations working for this animal. Donations open in Safari.
private struct HelpSection: View {
    let animal: Animal
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Help the \(animal.name)", systemImage: "heart.fill")
                .font(.title3.bold())
                .labelStyle(SectionLabelStyle(tint: .pink))
                .accessibilityAddTraits(.isHeader)

            Text("These groups work to protect the \(animal.name) and its home. Fauna takes no cut; donations go straight to them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(animal.charities) { charity in
                Button {
                    openURL(charity.url)
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.pink, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(charity.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(charity.blurb)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 4) {
                                Text("Donate at \(charity.host)")
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.pink)
                            .padding(.top, 4)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .accessibilityHint("Opens \(charity.host) in Safari")
            }
        }
    }
}

/// End-of-article call to action: answer up to three questions to unlock the next animal.
private struct UnlockCard: View {
    @Environment(AppStore.self) private var store
    let animal: Animal
    let start: () -> Void

    var body: some View {
        let inFocus = store.canUnlockInFocus
        let anywhere = store.canUnlockAnywhere
        VStack(spacing: 14) {
            Image(systemName: anywhere ? "sparkles" : "checkmark.seal.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)
                .padding(.bottom, 2)
            Text(anywhere ? "Curious for More?" : "You've Met Them All")
                .font(.title2.bold())
            Text(message(inFocus: inFocus, anywhere: anywhere))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if anywhere {
                Button(action: start) {
                    Text("Unlock Another Animal")
                }
                .buttonStyle(ProminentPillStyle())
                .padding(.top, 6)
            }
            if !inFocus && store.hasFocus {
                Button("Widen My Focus") { store.selectedTab = .focus }
                    .font(.subheadline.weight(.semibold))
            }
            if store.streak > 1 {
                Label("\(store.streak)-day streak", systemImage: "flame.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func message(inFocus: Bool, anywhere: Bool) -> String {
        let count = min(3, animal.quiz.count)
        let questions = count == 1 ? "one quick question" : "\(count) quick questions"
        if !anywhere {
            return "You've discovered every animal in Fauna. Come back tomorrow to revisit an old friend."
        }
        if !inFocus {
            return "You've met every animal in your focus. Answer \(questions) about the \(animal.name) to unlock one from anywhere in the world."
        }
        return "Answer \(questions) about the \(animal.name) to show you read it, and we'll introduce you to another."
    }
}
