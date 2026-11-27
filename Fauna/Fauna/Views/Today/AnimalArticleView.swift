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
    /// The end-of-article unlock card is on screen, so the floating unlock button steps aside.
    @State private var unlockCardVisible = false
    @State private var confirmUnlock = false
    /// A length or weight tapped in the facts: shown against something familiar.
    @State private var comparison: SizeComparison?

    /// On Today, once this animal's quiz is passed and the reader chose to wait: the next animal.
    private var waitingNext: Animal? {
        guard mode == .today, animal.id == store.currentAnimal?.id, store.isWaitingForTomorrow else { return nil }
        return store.reservedNext
    }

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
        // An overlay, not a safe-area inset: showing or hiding it must never change the
        // page's layout, or the scroll position jumps.
        .overlay(alignment: .bottom) {
            if mode == .today, let onStartQuiz, store.canUnlockAnywhere, !unlockCardVisible {
                Group {
                    if let next = waitingNext {
                        TomorrowPill(animal: next) { confirmUnlock = true }
                    } else {
                        UnlockPill(action: onStartQuiz)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: unlockCardVisible)
        .sheet(item: $comparison) { SizeComparisonView(animal: animal, comparison: $0).presentationDetents([.medium, .large]) }
        .confirmationDialog("Unlock your next animal now?", isPresented: $confirmUnlock, titleVisibility: .visible) {
            Button("Unlock now") {
                withAnimation(.smooth) { _ = store.unlockReservedNow() }
                Task { await Reminders.reschedule(store) }
            }
            Button("Wait for tomorrow", role: .cancel) {}
        } message: {
            Text("It's due tomorrow. Unlock it now and tomorrow still brings another.")
        }
        .task(id: animal.id) {
            // A passed quiz from an earlier visit: make sure tomorrow's animal is chosen.
            if mode == .today, store.hasPassedQuiz(animal), store.reservedNext == nil { store.reserveNext() }
        }
        .scrollIndicators(.hidden)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(pastHero ? nil : .dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
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
            ToolbarItem(placement: .topBarTrailing) {
                let saved = store.isBookmarked(animal)
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { store.toggleBookmark(animal) }
                } label: {
                    Image(systemName: saved ? "bookmark.fill" : "bookmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(saved ? Color.faunaGold : (pastHero ? Color.primary : .white))
                        .symbolEffect(.bounce, value: saved)
                        .frame(width: 36, height: 36)
                        .background(pastHero ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Material.ultraThinMaterial), in: Circle())
                }
                .accessibilityLabel(saved ? "Remove bookmark" : "Bookmark")
                .accessibilityIdentifier("article.bookmark")
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
                PhotoCreditLine(animal: animal, onDark: true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.35), in: Capsule())
                    .padding(.leading, 12)
                    .padding(.trailing, 56)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                .accessibilityIdentifier("article.title")
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

            FactGrid(facts: animal.facts.map { Fact(label: $0.label, value: store.measured($0.value)) }, tint: accent,
                     comparisons: animal.facts.map(SizeComparison.make(for:))) { comparison = $0 }
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

            if let relatives = animal.relatives, !relatives.isEmpty {
                ArticleSection(title: "Relatives and origins", symbol: "tree.fill", tint: accent) {
                    Paragraph(store.measured(relatives))
                }
            }

            if let people = animal.people, !people.isEmpty {
                ArticleSection(title: "People and the \(animal.name)", symbol: "person.2.fill", tint: accent) {
                    Paragraph(store.measured(people))
                }
            }

            ArticleSection(title: "Its future", symbol: "heart.fill", tint: accent) {
                VStack(alignment: .leading, spacing: 20) {
                    ConservationScale(status: animal.status)
                        .padding(16)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Paragraph(store.measured(animal.outlook))
                }
            }

            HelpSection(animal: animal)
                .id("help")

            sourceFooter

            if mode == .today, let onStartQuiz {
                Group {
                    if let next = waitingNext {
                        TomorrowCard(animal: next) { confirmUnlock = true }
                    } else {
                        UnlockCard(animal: animal, start: onStartQuiz)
                    }
                }
                    .id("unlock")
                    .onGeometryChange(for: Bool.self) { geo in
                        // Swap the floating button for the card only once the card's own
                        // "Unlock another animal" button (in its lower half) is clear of the
                        // tab bar, so there's never a moment with neither button usable.
                        let f = geo.frame(in: .global)
                        return f.minY + f.height * 0.75 < UIScreen.main.bounds.height - 100
                    } action: { visible in
                        unlockCardVisible = visible
                    }
            } else if mode == .journal {
                QuizCard(animal: animal, passed: store.hasPassedQuiz(animal))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        // Room for the floating unlock button, so it never covers the end of the page.
        .padding(.bottom, mode == .today ? 110 : 48)
    }

    private var sourceFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                        Text("This article is adapted and condensed from the Wikipedia article \u{201C}\(animal.wikipediaTitle)\u{201D} by its contributors, under CC BY-SA 4.0. Changes were made. This text is available under the same license.")
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
            HStack(spacing: 14) {
                Link("CC BY-SA 4.0 license", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
                PhotoCreditLine(animal: animal)
            }
            .font(.caption2)
            .padding(.leading, 36)
        }
    }
}

// MARK: - Pieces

private struct Paragraph: View {
    let text: String
    init(_ text: String) { self.text = text }
    /// Content separates paragraphs with a blank line.
    private var paragraphs: [String] {
        text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(FaunaFont.body)
                    .lineSpacing(5)
                    .foregroundStyle(Color.primary.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
    /// For each fact, a size comparison when it's a length or weight; those tiles can be tapped.
    var comparisons: [SizeComparison?] = []
    var onCompare: ((SizeComparison) -> Void)? = nil

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(Array(facts.enumerated()), id: \.offset) { i, fact in
                if let c = comparisons.indices.contains(i) ? comparisons[i] : nil, let onCompare {
                    Button { onCompare(c) } label: { tile(fact, comparable: true) }
                        .buttonStyle(PressableStyle())
                        .accessibilityHint(c.kind == .length ? "Compares its length with something familiar"
                                                             : "Compares its weight with something familiar")
                        .accessibilityIdentifier("fact.compare.\(fact.label.lowercased())")
                } else {
                    tile(fact, comparable: false)
                }
            }
        }
    }

    private func tile(_ fact: Fact, comparable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: fact.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
                if comparable {
                    // A gold "?" badge: clearly tappable, and set apart from the tile's own colour.
                    Image(systemName: "questionmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.black.opacity(0.75))
                        .frame(width: 24, height: 24)
                        .background(Color.faunaGold, in: Circle())
                        .shadow(color: Color.faunaGold.opacity(0.5), radius: 4)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(fact.value)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
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
                .strokeBorder(tint.opacity(comparable ? 0.3 : 0.12))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(fact.label): \(fact.value)")
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
                Button("Widen my focus") { store.showSettings = true }
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

/// End of a Journal article: take the animal's quiz, as often as you like. It never unlocks a
/// new animal (that happens on Today), but passing it marks the animal in your journal.
private struct QuizCard: View {
    let animal: Animal
    let passed: Bool
    @State private var showQuiz = false

    var body: some View {
        Button { showQuiz = true } label: {
            HStack(spacing: 14) {
                Image(systemName: passed ? "arrow.counterclockwise.circle.fill" : "questionmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.faunaMoss)
                VStack(alignment: .leading, spacing: 2) {
                    Text(passed ? "Retake the quiz" : "Take the quiz")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(passed ? "You passed this one. See if it stuck."
                                : "\(min(3, animal.quiz.count)) quick questions about the \(animal.name).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .fullScreenCover(isPresented: $showQuiz) { QuizView(animal: animal, practice: true) }
    }
}

/// Floating button on Today: the one obvious way to get the next animal.
private struct UnlockPill: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Unlock the next animal")
                        .font(.subheadline.weight(.bold))
                    Text("3 quick questions about this one")
                        .font(.caption)
                        .opacity(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.faunaMoss, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Answer three questions about this animal to unlock another")
    }
}

/// The next animal, photo blurred so it stays a surprise. Its name is never shown or spoken.
struct HiddenAnimalTile: View {
    let animal: Animal
    let caption: String
    var height: CGFloat = 150

    var body: some View {
        AnimalPhoto(animal: animal, size: .card)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .blur(radius: 22, opaque: true)
            .overlay(Color.black.opacity(0.25))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                    Text(caption)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(caption). It stays hidden until you meet it.")
    }
}

/// End of today's article once its quiz is passed: tomorrow's animal, blurred, with the
/// option to unlock it early.
private struct TomorrowCard: View {
    let animal: Animal
    let unlockNow: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            HiddenAnimalTile(animal: animal, caption: "Unlocks tomorrow", height: 190)
            VStack(spacing: 8) {
                Text("Quiz passed")
                    .font(FaunaFont.display(26))
                    .foregroundStyle(.white)
                Text("Your next animal arrives tomorrow. Can't wait? Unlock it now.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: unlockNow) {
                Label("Unlock it now", systemImage: "lock.open.fill")
            }
            .buttonStyle(ProminentPillStyle(tint: .faunaMoss))
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.faunaForest))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
    }
}

/// Floating bar on Today while the next animal waits for tomorrow.
private struct TomorrowPill: View {
    let animal: Animal
    let unlockNow: () -> Void

    var body: some View {
        Button(action: unlockNow) {
            HStack(spacing: 12) {
                AnimalPhoto(animal: animal, size: .card)
                    .frame(width: 34, height: 34)
                    .blur(radius: 6, opaque: true)
                    .clipShape(Circle())
                    .overlay(Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Next animal unlocks tomorrow")
                        .font(.subheadline.weight(.bold))
                    Text("Tap to unlock it now")
                        .font(.caption)
                        .opacity(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.faunaForest, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next animal unlocks tomorrow")
        .accessibilityHint("Unlocks it now, after you confirm")
        .accessibilityAddTraits(.isButton)
    }
}
