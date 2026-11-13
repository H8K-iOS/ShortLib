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
                    // Свет обложки: книга в центре, за ней — неподвижное свечение в её тоне.
                    ZStack {
                        Circle()
                            .fill(DS.Color.coverGlow(style: book.coverStyle, radius: 190))
                            .frame(width: 380, height: 380)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        BookCover(title: book.title, caption: book.source.kindTitle, style: book.coverStyle, showsText: false)
                            .frame(width: 150, height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                                .stroke(DS.Color.line, lineWidth: 1))
                            .dsElasticDrag(limit: 40)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 250)

                    VStack(spacing: DS.Space.s) {
                        Text(book.title).font(DS.Font.largeTitle).multilineTextAlignment(.center)
                        Text("\(book.author) · \(book.source.kindTitle) · \(book.language)").dsOverline()
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    // Главное о книге — плитками с крупными цифрами.
                    HStack(spacing: DS.Space.s) {
                        StatTile(value: "\(book.chapters.count)", label: "глав")
                        StatTile(value: viewModel.originalReadingTime.replacingOccurrences(of: "≈ ", with: ""),
                                 label: "оригинал")
                        if let summary = book.summary {
                            StatTile(value: "\(summary.readingMinutes)", unit: "мин", label: "пересказ")
                        }
                    }

                    if let progress = viewModel.partialProgressText {
                        Label(viewModel.isGenerating ? "Пересказываем · \(progress.lowercased())"
                                                     : "Пересказ остановлен · \(progress.lowercased())",
                              systemImage: "hourglass")
                            .font(DS.Font.callout)
                    }

                    HStack(spacing: DS.Space.m) {
                        Text(String(book.source.hostTitle.prefix(1)).uppercased())
                            .font(DS.Font.headline).foregroundColor(DS.Color.ink)
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

                    // Главы — блоком-виджетом с номерами «01, 02».
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Главы").dsOverline()
                            Spacer()
                            Text(viewModel.loadedChaptersText).dsOverline()
                        }
                        .padding(.bottom, DS.Space.s)
                        ForEach(book.chapters.prefix(6)) { chapter in
                            HStack(spacing: DS.Space.m) {
                                Text(String(format: "%02d", chapter.index)).dsOverline()
                                    .frame(width: 24, alignment: .leading)
                                Text(chapter.title).font(DS.Font.callout).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, DS.Space.s)
                            .overlay(alignment: .top) { Rectangle().fill(DS.Color.line).frame(height: 1) }
                        }
                        if book.chapters.count > 6 {
                            Text("и ещё \(book.chapters.count - 6)").dsOverline()
                                .padding(.top, DS.Space.s)
                        }
                    }
                    .padding(DS.Space.l)
                    .background(DS.Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous).stroke(DS.Color.line, lineWidth: 1))
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
