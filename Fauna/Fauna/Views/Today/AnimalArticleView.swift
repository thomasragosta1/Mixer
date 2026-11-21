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
    @State private var heroImage: UIImage?
    @State private var viewSize: CGSize = CGSize(width: 393, height: 852)
    @State private var topInset: CGFloat = 59
    @State private var showPhoto = false

    /// The photo is shown whole: the header takes the photo's own shape (within sensible limits)
    /// and any leftover space is filled with a soft blur of the same photo.
    private var heroHeight: CGFloat {
        let w = viewSize.width
        let ratio = heroImage.map { $0.size.height / max($0.size.width, 1) } ?? 0.75
        let natural = w * ratio + topInset
        return min(max(natural, w * 0.62 + topInset), viewSize.height * 0.72)
    }
    private var accent: Color { animal.group.color }

    var body: some View {
        ZStack(alignment: .top) {
            article
                .background(Color(.systemBackground))
                .ignoresSafeArea(edges: .top)
            // Pinned to the top of the safe area; its material extends up under the status bar.
            Text(animal.name)
                .font(.system(.headline, design: .serif))
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
            if mode == .today, let onStartQuiz, store.canUnlockAnywhere {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onStartQuiz) {
                        Label("Next animal", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(pastHero ? Color.primary : .white)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(pastHero ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Material.ultraThinMaterial), in: Capsule())
                    }
                    .accessibilityHint("Answer three questions about this animal to unlock another")
                }
            }
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
                }
            }
            .task { await scrollForScreenshot(proxy) }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
        .background {
            GeometryReader { geo in
                Color.clear.onAppear { topInset = max(geo.safeAreaInsets.top, 20) }
            }
        }
        .task(id: animal.id) {
            heroImage = await WikiImages.shared.image(for: animal.wikipediaTitle, size: .hero)
        }
        .fullScreenCover(isPresented: $showPhoto) {
            PhotoViewer(animal: animal, preview: heroImage)
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
            let parallax = minY < 0 ? -minY * 0.3 : 0
            ZStack(alignment: .bottom) {
                // Backdrop: the same photo, blurred, filling whatever the photo doesn't.
                AnimalPhoto(animal: animal, size: .card)
                    .blur(radius: 30)
                    .scaleEffect(1.2)
                    .overlay(Color.black.opacity(0.15))
                if let heroImage {
                    Image(uiImage: heroImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: heroHeight + stretch - topInset,
                               alignment: .bottom)
                        .transition(.opacity)
                }
                LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .center)
                    .frame(height: topInset * 2)
                    .frame(maxHeight: .infinity, alignment: .top)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
                    .environment(\.colorScheme, .dark)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .offset(y: parallax)
            .frame(width: geo.size.width, height: heroHeight + stretch)
            .clipped()
            .offset(y: -stretch)
            .contentShape(Rectangle())
            .onTapGesture { showPhoto = true }
            .accessibilityElement()
            .accessibilityLabel("Photo of the \(animal.name)")
            .accessibilityHint("Opens the photo full screen")
            .accessibilityAddTraits(.isButton)
        }
        .frame(height: heroHeight)
        .animation(.easeOut(duration: 0.35), value: heroImage == nil)
        .onGeometryChange(for: Bool.self) { geo in
            geo.frame(in: .scrollView).minY < -(heroHeight - topInset - 20)
        } action: { past in
            withAnimation(.easeInOut(duration: 0.25)) { pastHero = past }
        }
    }

    private var heroTitle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(eyebrowText, color: accent)
            Text(animal.name)
                .font(FaunaFont.display(titleSize))
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            Text(animal.scientificName)
                .font(.system(.title3, design: .serif).italic())
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Label(animal.group.singular, systemImage: animal.group.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(animal.group.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(animal.group.color.opacity(0.13), in: Capsule())
                StatusPill(status: animal.status)
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
        VStack(alignment: .leading, spacing: 36) {
            heroTitle

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 6) {
                    Image(systemName: "book.pages")
                    Text("\(animal.readingMinutes) min read · Condensed from Wikipedia")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

                Text("“\(animal.tagline)”")
                    .font(FaunaFont.display(27, weight: .semibold))
                    .foregroundStyle(accent)
                    .fixedSize(horizontal: false, vertical: true)

                Text(store.measured(animal.lede))
                    .font(FaunaFont.lede)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FactGrid(facts: animal.facts.map { Fact(label: $0.label, value: store.measured($0.value)) }, tint: accent)
                .id("facts")

            ArticleSection(title: "Where it lives", symbol: "map.fill", tint: accent) {
                VStack(alignment: .leading, spacing: 16) {
                    RangeMap(animal: animal)
                        .frame(height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            Label(store.measured(animal.range), systemImage: "location.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .environment(\.colorScheme, .dark)
                                .padding(10)
                        }
                    Paragraph(store.measured(animal.home))
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

            if let anatomy = animal.anatomy, !anatomy.isEmpty {
                ArticleSection(title: "Body and senses", symbol: "eye.fill", tint: accent) {
                    Paragraph(store.measured(anatomy))
                }
            }

            ArticleSection(title: "How it lives", symbol: "leaf.fill", tint: accent) {
                Paragraph(store.measured(animal.life))
            }

            if let family = animal.family, !family.isEmpty {
                ArticleSection(title: "Family life", symbol: "figure.2.and.child.holdinghands", tint: accent) {
                    Paragraph(store.measured(family))
                }
            }

            ArticleSection(title: "What makes it remarkable", symbol: "sparkles", tint: accent) {
                Paragraph(store.measured(animal.remarkable))
            }

            DidYouKnowCard(text: store.measured(animal.didYouKnow), tint: accent)
                .id("didYouKnow")

            ArticleSection(title: "Its future", symbol: "heart.fill", tint: accent) {
                VStack(alignment: .leading, spacing: 20) {
                    ConservationScale(status: animal.status)
                        .padding(16)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Paragraph(store.measured(animal.outlook))
                }
            }

            if let people = animal.people, !people.isEmpty {
                ArticleSection(title: "People and the \(animal.name)", symbol: "person.2.fill", tint: accent) {
                    Paragraph(store.measured(people))
                }
            }

            if let relatives = animal.relatives, !relatives.isEmpty {
                ArticleSection(title: "Relatives and origins", symbol: "tree.fill", tint: accent) {
                    Paragraph(store.measured(relatives))
                }
            }

            HelpSection(animal: animal)
                .id("help")

            sourceFooter

            if mode == .today, let onStartQuiz {
                UnlockCard(animal: animal, start: onStartQuiz)
                    .id("unlock")
            } else if mode == .journal {
                PracticeCard(animal: animal, passed: store.hasPassedQuiz(animal))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
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
            .lineSpacing(5)
            .foregroundStyle(Color.primary.opacity(0.88))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ArticleSection<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(FaunaFont.display(22))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content
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
                            .font(.system(.headline, design: .rounded))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(fact.label.uppercased())
                            .font(.caption2.weight(.semibold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(tint.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(tint.opacity(0.12))
                )
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
        VStack(alignment: .leading, spacing: 12) {
            Label("Did you know?", systemImage: "lightbulb.max.fill")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(.white.opacity(0.9))
            Text(text)
                .font(FaunaFont.display(20, weight: .medium))
                .foregroundStyle(.white)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(tint.blended(with: .black, by: 0.15))
            Image(systemName: "sparkles")
                .font(.system(size: 120))
                .foregroundStyle(.white.opacity(0.07))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 20, y: -20)
                .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// Foundations working for this animal. Donations open in Safari.
private struct HelpSection: View {
    let animal: Animal
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "hands.and.sparkles.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.pink, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("Help the \(animal.name)")
                    .font(FaunaFont.display(22))
            }
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
                        Text(String(charity.name.prefix(1)))
                            .font(FaunaFont.display(20))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.pink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .padding(16)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(.white.opacity(0.12)).frame(width: 74, height: 74)
                Image(systemName: anywhere ? "lock.open.fill" : "checkmark.seal.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.faunaGold)
                    .symbolEffect(.pulse, options: .repeating.speed(0.5))
            }
            VStack(spacing: 8) {
                Text(anywhere ? "Curious for more?" : "You've met them all")
                    .font(FaunaFont.display(26))
                    .foregroundStyle(.white)
                Text(message(inFocus: inFocus, anywhere: anywhere))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if anywhere {
                Button(action: start) {
                    Label("Unlock another animal", systemImage: "sparkles")
                }
                .buttonStyle(ProminentPillStyle(tint: .faunaMoss))
            }
            if !inFocus && store.hasFocus {
                Button("Widen my focus") { store.selectedTab = .focus }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.faunaGold)
            }
            if store.streak > 1 {
                Label("\(store.streak)-day streak", systemImage: "flame.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.faunaForest)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
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

/// End of a Journal article: re-take the quiz for practice.
private struct PracticeCard: View {
    let animal: Animal
    let passed: Bool
    @State private var showQuiz = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: passed ? "checkmark.seal.fill" : "questionmark.bubble.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(passed ? Color.faunaGold : Color.faunaMoss)
            Text("Test yourself")
                .font(FaunaFont.display(24))
            Text(passed ? "You've passed this one before. See if it stuck." : "Three questions about the \(animal.name). No pressure.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { showQuiz = true } label: { Text("Start quiz") }
                .buttonStyle(ProminentPillStyle(tint: .faunaMoss))
        }
        .fullScreenCover(isPresented: $showQuiz) { QuizView(animal: animal, practice: true) }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}
