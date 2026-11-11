import SwiftUI

struct SummaryReaderView: View {
    @ObservedObject var viewModel: SummaryReaderViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.s) {
                CircleIconButton(systemImage: "chevron.left", accessibilityTitle: "Назад", action: viewModel.back)
                Spacer()
                StatusBadge(text: "Готово", style: .success, systemImage: "checkmark")
                ShareLink(item: viewModel.shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(DS.Font.label)
                        .foregroundColor(DS.Color.ink)
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(DS.Color.line, lineWidth: 1))
                }
                .accessibilityLabel("Поделиться")
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.s)

            if let book = viewModel.book, let summary = viewModel.summary {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.l) {
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            Text(book.title).font(DS.Font.largeTitle)
                            Text(viewModel.metaText).font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                        }

                        HStack(spacing: DS.Space.xl) {
                            ForEach(viewModel.tabs) { tab in
                                Button { viewModel.tab = tab } label: {
                                    VStack(spacing: DS.Space.s) {
                                        Text(tab.title).font(DS.Font.headline)
                                            .foregroundColor(viewModel.tab == tab ? DS.Color.ink : DS.Color.secondary)
                                        Rectangle().fill(viewModel.tab == tab ? DS.Color.ink : Color.clear).frame(height: 2)
                                    }
                                    .fixedSize()
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }
                        .overlay(alignment: .bottom) { Rectangle().fill(DS.Color.line).frame(height: 1) }

                        switch viewModel.tab {
                        case .overview:
                            Text(summary.overview).font(DS.Font.body).lineSpacing(4)
                        case .chapters:
                            LazyVStack(alignment: .leading, spacing: DS.Space.xl) {
                                ForEach(summary.chapters) { chapter in
                                    VStack(alignment: .leading, spacing: DS.Space.s) {
                                        Text("Глава \(chapter.index) · \(chapter.title)").font(DS.Font.headline)
                                        Text(chapter.text).font(DS.Font.body).lineSpacing(4)
                                        if let links = chapter.connections {
                                            Label(links, systemImage: "link")
                                                .font(DS.Font.callout)
                                                .foregroundColor(DS.Color.secondary)
                                                .padding(DS.Space.m)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(DS.Color.surface)
                                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                                        }
                                    }
                                }
                            }
                        case .characters:
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(summary.characters ?? []) { person in
                                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                                        Text(person.name).font(DS.Font.headline)
                                        Text(person.note).font(DS.Font.callout).foregroundColor(DS.Color.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, DS.Space.m)
                                    .overlay(alignment: .bottom) { Rectangle().fill(DS.Color.line).frame(height: 1) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DS.Space.l)
                    .padding(.bottom, DS.Space.xxl)
                    .textSelection(.enabled)
                }
            } else {
                Spacer()
                Text("Пересказ не найден").font(DS.Font.callout).foregroundColor(DS.Color.secondary)
                Spacer()
            }
        }
    }
}
