import SwiftUI

struct SummariesView: View {
    @ObservedObject var viewModel: SummariesViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                Text("Пересказы").font(DS.Font.largeTitle).padding(.top, DS.Space.l)

                if viewModel.books.isEmpty {
                    Text("Готовые пересказы появятся здесь. Откройте книгу в библиотеке и нажмите «Пересказать».")
                        .font(DS.Font.body).foregroundColor(DS.Color.secondary)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.books) { book in
                            Button { viewModel.select(book) } label: { row(book) }
                                .buttonStyle(PressScaleStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Space.l)
        }
    }

    private func row(_ book: Book) -> some View {
        HStack(spacing: DS.Space.m) {
            BookCover(title: "", caption: "", style: book.coverStyle, showsText: false)
                .frame(width: 56, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title).font(DS.Font.headline).lineLimit(1)
                if let s = book.summary {
                    Text("\(s.preset.level.title) · ≈ \(s.readingMinutes) мин").font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(DS.Font.caption).foregroundColor(DS.Color.secondary)
        }
        .foregroundColor(DS.Color.ink)
        .padding(.vertical, DS.Space.m)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.Color.line).frame(height: 1) }
    }
}
