import SwiftUI

struct LibraryView: View {
    @ObservedObject var viewModel: LibraryViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                SearchPill(title: "Что пересказать?", subtitle: "EPUB или ссылка на новеллу", action: viewModel.addBook)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.xl) {
                        CategoryTab(title: "Все", systemImage: "square.stack", isOn: viewModel.selectedGenre == nil) {
                            viewModel.selectedGenre = nil
                        }
                        ForEach(viewModel.genres) { genre in
                            CategoryTab(title: genre.title, systemImage: genre.systemImage, isOn: viewModel.selectedGenre == genre) {
                                viewModel.selectedGenre = genre
                            }
                        }
                    }
                }
                Rectangle().fill(DS.Color.line).frame(height: 1).padding(.top, -DS.Space.l)

                if viewModel.visibleBooks.isEmpty {
                    EmptyLibraryView(action: viewModel.addBook)
                } else {
                    LazyVStack(spacing: DS.Space.xl) {
                        ForEach(viewModel.visibleBooks) { book in
                            Button { viewModel.select(book) } label: {
                                BookCard(book: book, isGenerating: viewModel.isGenerating(book))
                            }
                                .buttonStyle(PressScaleStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.s)
        }
    }
}

struct BookCard: View {
    let book: Book
    var isGenerating = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            BookCover(title: book.title, caption: book.source.kindTitle, style: book.coverStyle)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                .overlay(alignment: .topLeading) {
                    StatusBadge(text: badgeText, systemImage: isGenerating ? "hourglass" : nil)
                        .padding(DS.Space.m)
                }

            HStack(alignment: .firstTextBaseline) {
                Text(book.title).font(DS.Font.headline).lineLimit(1)
                Spacer()
                if let level = book.summary?.preset.level {
                    Label(level.title, systemImage: "star.fill").font(DS.Font.caption).labelStyle(.titleAndIcon)
                }
            }
            Text(meta).font(DS.Font.callout).foregroundColor(DS.Color.secondary)
        }
        .foregroundColor(DS.Color.ink)
        .multilineTextAlignment(.leading)
    }

    /// «Пересказываем · 12 из 33», «Готово 12 из 33», «Пересказ готов» или число глав.
    private var badgeText: String {
        if let partial = book.partialSummary {
            let progress = "\(partial.chapters.count) из \(partial.preset.chapterRange.count)"
            return isGenerating ? "Пересказываем · \(progress)" : "Готово \(progress)"
        }
        if isGenerating { return "Пересказываем" }
        return book.summary == nil ? "\(book.chapters.count) глав" : "Пересказ готов"
    }

    private var meta: String {
        if let summary = book.summary {
            let r = summary.preset.chapterRange
            return "Главы \(r.lowerBound)–\(r.upperBound) из \(book.chapters.count) · ≈ \(summary.readingMinutes) мин чтения"
        }
        return "\(book.author) · \(book.source.hostTitle)"
    }
}

private struct EmptyLibraryView: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("Здесь будут ваши книги").font(DS.Font.title)
            Text("Добавьте EPUB из «Файлов» или вставьте ссылку на оглавление веб-новеллы.")
                .font(DS.Font.body).foregroundColor(DS.Color.secondary)
            PrimaryButton(title: "Добавить книгу", action: action)
        }
        .padding(.top, DS.Space.xxl)
    }
}
