import SwiftUI

struct ImportView: View {
    @ObservedObject var viewModel: ImportViewModel
    @FocusState private var isURLFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CircleIconButton(systemImage: "xmark", accessibilityTitle: "Закрыть", action: viewModel.close)
                Spacer()
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.top, DS.Space.l)

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    Text("Откуда берём книгу?").font(DS.Font.largeTitle)

                    option(kind: .epub, symbol: "doc.text", title: "Файл EPUB",
                           subtitle: "Из «Файлов», iCloud Drive или через «Поделиться» в другом приложении")
                    option(kind: .web, symbol: "link", title: "Веб-новелла по ссылке",
                           subtitle: "Вставьте адрес страницы с оглавлением — главы найдём сами")

                    if viewModel.kind == .web {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ссылка на оглавление").font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                            TextField("https://…", text: $viewModel.urlText)
                                .font(DS.Font.headline)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($isURLFocused)
                                .submitLabel(.search)
                                .onSubmit(viewModel.primaryAction)
                                .onChange(of: viewModel.urlText) { _ in viewModel.urlChanged() }
                        }
                        .padding(.horizontal, DS.Space.m)
                        .padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.s).stroke(isURLFocused ? DS.Color.ink : DS.Color.secondary, lineWidth: isURLFocused ? 2 : 1))
                    }

                    stateView
                }
                .padding(DS.Space.l)
                .animation(DS.Motion.respecting(DS.Motion.standard), value: viewModel.kind)
            }

            FooterBar {
                TextLinkButton(title: "Отмена", action: viewModel.close)
            } trailing: {
                PrimaryButton(title: viewModel.primaryTitle, isEnabled: viewModel.canContinue, action: viewModel.primaryAction)
            }
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()
        case .loading(let text):
            HStack(spacing: DS.Space.m) {
                ProgressView().tint(DS.Color.accent)
                Text(text).font(DS.Font.callout).foregroundColor(DS.Color.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.circle")
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.accent)
        case .preview(let preview):
            HStack(spacing: DS.Space.m) {
                BookCover(title: "", caption: "", style: 0, showsText: false)
                    .frame(width: 44, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.title).font(DS.Font.headline).lineLimit(2)
                    Text("Найдено \(preview.links.count) глав · \(preview.sourceURL.host ?? "")")
                        .font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.m)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
        }
    }

    private func option(kind: ImportViewModel.SourceKind, symbol: String, title: String, subtitle: String) -> some View {
        let isOn = viewModel.kind == kind
        return Button { viewModel.select(kind) } label: {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Image(systemName: symbol).font(DS.Font.icon)
                Text(title).font(DS.Font.headline)
                Text(subtitle).font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(DS.Color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.l)
            .background(DS.Color.card)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                .stroke(isOn ? DS.Color.ink : DS.Color.line, lineWidth: isOn ? 2 : 1))
        }
        .buttonStyle(PressScaleStyle())
    }
}
