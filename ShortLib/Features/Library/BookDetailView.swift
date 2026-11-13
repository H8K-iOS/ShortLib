import SwiftUI

struct BookDetailView: View {
    @ObservedObject var viewModel: BookDetailViewModel
    @State private var isConfirmingDelete = false

    var body: some View {
        if let book = viewModel.book {
            content(book)
        } else {
            Color.clear
        }
    }

    private func content(_ book: Book) -> some View {
        VStack(spacing: 0) {
            HStack {
                CircleIconButton(systemImage: "chevron.left", accessibilityTitle: "Назад", action: viewModel.back)
                Spacer()
                CircleIconButton(systemImage: "trash", accessibilityTitle: "Удалить") { isConfirmingDelete = true }
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.s)

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    BookCover(title: book.title, caption: book.source.kindTitle, style: book.coverStyle, showsText: false)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))

                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text(book.title).font(DS.Font.largeTitle)
                        Text("\(book.author) · \(book.source.kindTitle) · \(book.language)")
                            .font(DS.Font.callout).foregroundColor(DS.Color.secondary)
                    }

                    HStack(spacing: DS.Space.m) {
                        Text(String(book.source.hostTitle.prefix(1)).uppercased())
                            .font(DS.Font.headline).foregroundColor(DS.Color.accent)
                            .frame(width: 40, height: 40)
                            .background(DS.Color.surface).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Источник: \(book.source.hostTitle)").font(DS.Font.headline).lineLimit(1)
                            Text("Добавлено \(book.addedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                        }
                    }
                    .padding(.vertical, DS.Space.m)
                    .overlay(alignment: .top) { Rectangle().fill(DS.Color.line).frame(height: 1) }
                    .overlay(alignment: .bottom) { Rectangle().fill(DS.Color.line).frame(height: 1) }

                    VStack(alignment: .leading, spacing: DS.Space.m) {
                        fact("square.stack", viewModel.loadedChaptersText)
                        fact("clock", "Оригинал \(viewModel.originalReadingTime)")
                        if let progress = viewModel.partialProgressText {
                            fact("hourglass", viewModel.isGenerating ? "Пересказываем · \(progress.lowercased())"
                                                                     : "Пересказ остановлен · \(progress.lowercased())")
                        } else if let summary = book.summary {
                            fact("doc.text", "Пересказ: \(summary.preset.level.title.lowercased()), ≈ \(summary.readingMinutes) мин")
                        }
                    }

                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text("Главы").font(DS.Font.title)
                        ForEach(book.chapters.prefix(6)) { chapter in
                            HStack(spacing: DS.Space.m) {
                                Text("\(chapter.index)").font(DS.Font.caption.monospacedDigit())
                                    .foregroundColor(DS.Color.secondary).frame(width: 28, alignment: .leading)
                                Text(chapter.title).font(DS.Font.callout).lineLimit(1)
                            }
                        }
                        if book.chapters.count > 6 {
                            Text("и ещё \(book.chapters.count - 6)").font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                        }
                    }
                }
                .padding(.horizontal, DS.Space.l)
                .padding(.bottom, DS.Space.xl)
            }

            footer(book)
        }
        .confirmationDialog("Удалить «\(book.title)»?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Удалить книгу и пересказ", role: .destructive, action: viewModel.delete)
        }
    }

    @ViewBuilder
    private func footer(_ book: Book) -> some View {
        if viewModel.isGenerating {
            // Пересказ идёт в фоне: вернуться к прогрессу или читать готовые главы.
            FooterBar {
                if viewModel.canRead {
                    TextLinkButton(title: "Читать готовое", action: viewModel.read)
                } else {
                    Text("Пересказываем…").font(DS.Font.headline)
                }
            } trailing: {
                PrimaryButton(title: "Открыть прогресс", action: viewModel.resume)
            }
        } else if viewModel.canResume {
            // Пересказ остановился (ошибка, отмена, iOS) — готовые главы сохранены.
            FooterBar {
                if viewModel.canRead {
                    TextLinkButton(title: "Читать готовое", action: viewModel.read)
                }
            } trailing: {
                PrimaryButton(title: "Продолжить пересказ", action: viewModel.resume)
            }
        } else if let summary = book.summary {
            FooterBar {
                TextLinkButton(title: "Пересказать заново", action: viewModel.summarize)
            } trailing: {
                PrimaryButton(title: "Читать · \(summary.readingMinutes) мин", action: viewModel.read)
            }
        } else {
            FooterBar {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(book.chapters.count) глав").font(DS.Font.headline)
                    Text("Выберите детальность").font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                }
            } trailing: {
                PrimaryButton(title: "Пересказать", action: viewModel.summarize)
            }
        }
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: DS.Space.m) {
            Image(systemName: symbol).font(DS.Font.headline).frame(width: 24)
            Text(text).font(DS.Font.callout)
        }
    }
}
