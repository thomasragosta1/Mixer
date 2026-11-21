import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var quizAnimal: Animal?

    var body: some View {
        NavigationStack {
            Group {
                if let animal = store.currentAnimal {
                    AnimalArticleView(animal: animal, mode: .today) { quizAnimal = animal }
                        .id(animal.id)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.04)),
                                                removal: .opacity))
                } else {
                    ContentUnavailableView("No animal yet",
                                           systemImage: "pawprint",
                                           description: Text("Your first animal arrives as soon as you finish setting up."))
                }
            }
            .animation(.smooth(duration: 0.6), value: store.currentAnimal?.id)
            .navigationDestination(for: Animal.self) { AnimalArticleView(animal: $0, mode: .journal) }
        }
        .sheet(item: $quizAnimal) { QuizView(animal: $0) }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-FaunaQuiz") { quizAnimal = store.currentAnimal }
        }
        .task(id: store.currentAnimal?.id) {
            // Warm tomorrow's photo so the next day opens instantly.
            let titles = store.upcomingDailyAnimals(count: 2).map(\.wikipediaTitle)
            await WikiImages.shared.prefetch(titles, size: .hero)
        }
    }
}
