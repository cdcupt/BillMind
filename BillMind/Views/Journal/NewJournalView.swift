import SwiftUI
import SwiftData

struct NewJournalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedCurrency = "CNY"
    @State private var selectedAnimal: AnimalType = .cat
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Animal picker
                    VStack(spacing: 8) {
                        Text("Choose a mascot")
                            .font(SketchTheme.captionFont())
                            .foregroundStyle(SketchTheme.lightBrown)
                        HStack(spacing: 16) {
                            ForEach(AnimalType.allCases) { animal in
                                Button {
                                    selectedAnimal = animal
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(animal.imageName)
                                            .resizable().scaledToFit()
                                            .frame(width: 44, height: 44)
                                        Text(animal.displayName)
                                            .font(SketchTheme.captionFont(11))
                                            .foregroundStyle(
                                                selectedAnimal == animal
                                                    ? SketchTheme.dustyRose
                                                    : SketchTheme.lightBrown
                                            )
                                    }
                                    .padding(8)
                                    .background(
                                        selectedAnimal == animal
                                            ? SketchTheme.dustyRose.opacity(0.1)
                                            : Color.clear
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                selectedAnimal == animal
                                                    ? SketchTheme.dustyRose.opacity(0.5)
                                                    : Color.clear,
                                                lineWidth: 1.5
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .sketchCard()

                    // Name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Journal Name")
                            .font(SketchTheme.captionFont())
                            .foregroundStyle(SketchTheme.lightBrown)
                        TextField("e.g., Tokyo Trip 2026", text: $name)
                            .font(SketchTheme.bodyFont())
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(SketchTheme.cream)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(SketchTheme.lightBrown.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .sketchCard()

                    // Currency picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Currency")
                            .font(SketchTheme.captionFont())
                            .foregroundStyle(SketchTheme.lightBrown)
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                        ], spacing: 8) {
                            ForEach(CurrencyInfo.popular) { currency in
                                Button {
                                    selectedCurrency = currency.code
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(currency.symbol)
                                            .font(SketchTheme.headlineFont(16))
                                        Text(currency.code)
                                            .font(SketchTheme.captionFont(11))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        selectedCurrency == currency.code
                                            ? SketchTheme.dustyRose.opacity(0.15)
                                            : SketchTheme.cream
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(
                                                selectedCurrency == currency.code
                                                    ? SketchTheme.dustyRose.opacity(0.5)
                                                    : SketchTheme.lightBrown.opacity(0.2),
                                                lineWidth: 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(SketchTheme.softBrown)
                            }
                        }
                    }
                    .sketchCard()

                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (optional)")
                            .font(SketchTheme.captionFont())
                            .foregroundStyle(SketchTheme.lightBrown)
                        TextField("Trip details, dates, companions...", text: $notes, axis: .vertical)
                            .font(SketchTheme.bodyFont(14))
                            .textFieldStyle(.plain)
                            .lineLimit(3...6)
                            .padding(12)
                            .background(SketchTheme.cream)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(SketchTheme.lightBrown.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .sketchCard()

                    // Create button
                    Button {
                        createJournal()
                    } label: {
                        HandDrawnButton(title: "Create Journal", icon: nil, style: .primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                }
                .padding()
            }
            .paperBackground()
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("New Journal")
                        .font(SketchTheme.headlineFont(20))
                        .foregroundStyle(SketchTheme.softBrown)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(SketchTheme.dustyRose)
                }
            }
        }
    }

    private func createJournal() {
        let journal = Journal(
            name: name.trimmingCharacters(in: .whitespaces),
            currency: selectedCurrency,
            coverAnimal: selectedAnimal,
            notes: notes.isEmpty ? nil : notes
        )
        modelContext.insert(journal)
        try? modelContext.save()
        dismiss()
    }
}
