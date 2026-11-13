import SwiftUI

struct SummaryReaderView: View {
    @ObservedObject var viewModel: SummaryReaderViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.s) {
                CircleIconButton(systemImage: "chevron.left", accessibilityTitle: "Назад", action: viewModel.back)
                Spacer()
                if viewModel.isInProgress {
                    StatusBadge(text: viewModel.progressBadge)
                        .overlay(Capsule().stroke(DS.Color.line, lineWidth: 1))
                        .accessibilityLabel("Готово \(viewModel.readyChapters) из \(viewModel.totalChapters) глав")
                } else {
                    StatusBadge(text: "Готово", style: .success, systemImage: "checkmark")
                }
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

            if let book = viewModel.book, viewModel.hasContent {
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.l) {
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            Text(book.title).font(DS.Font.largeTitle)
                            Text(viewModel.metaText).font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                        }

                        tabBar

                        switch viewModel.tab {
                        case .overview:
                            if let overview = viewModel.overview {
                                // Пока не подтвердили — весь текст размыт и недоступен VoiceOver и выделению.
                                Text(overview).font(DS.Font.body).lineSpacing(4)
                                    .blur(radius: viewModel.isOverviewHidden ? 9 : 0)
                                    .accessibilityHidden(viewModel.isOverviewHidden)
                                    .allowsHitTesting(!viewModel.isOverviewHidden)
                            } else {
                                NoticeCard(systemImage: "hourglass",
                                           title: "Сводка будет готова после всех глав",
                                           message: "Связи между главами тоже появятся в конце. Пока можно читать по главам.") {
                                    SecondaryButton(title: "Читать по главам", action: viewModel.showChapters)
                                }
                            }
                        case .chapters:
                            LazyVStack(alignment: .leading, spacing: DS.Space.m) {
                                if viewModel.chapters.count > 1 {
                                    HStack {
                                        Spacer()
                                        Button(viewModel.isAllExpanded ? "Свернуть все" : "Раскрыть все",
                                               action: viewModel.toggleAll)
                                            .font(DS.Font.label)
                                            .foregroundColor(DS.Color.secondary)
                                    }
                                }
                                ForEach(viewModel.chapters) { chapter in
                                    ChapterCard(chapter: chapter,
                                                isExpanded: viewModel.isExpanded(chapter),
                                                next: viewModel.next(after: chapter),
                                                onToggle: { viewModel.toggle(chapter) },
                                                onNext: { viewModel.openNext(after: chapter) })
                                        .id(chapter.index)
                                        .transition(.opacity)
                                }
                                if viewModel.isInProgress {
                                    pendingCard
                                }
                            }
                            .animation(DS.Motion.respecting(DS.Motion.standard), value: viewModel.chapters.count)
                        case .characters:
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(viewModel.characters) { person in
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
                // «Дальше»: прокрутить к началу следующей главы.
                .onChange(of: viewModel.scrollTarget) { target in
                    guard let target else { return }
                    withAnimation(DS.Motion.respecting(DS.Motion.standard)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
                }
            } else {
                Spacer()
                Text("Пересказ не найден").font(DS.Font.callout).foregroundColor(DS.Color.secondary)
                Spacer()
            }
        }
        .overlay {
            if viewModel.isOverviewHidden {
                SpoilerGate(onReveal: viewModel.revealOverview, onCancel: viewModel.showChapters)
                    .transition(.opacity)
            }
        }
        .animation(DS.Motion.respecting(DS.Motion.standard), value: viewModel.isOverviewHidden)
    }

    private var tabBar: some View {
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
    }

    /// Плашка под готовыми главами: следующая глава готовится или пересказ остановлен.
    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(viewModel.pendingTitle).font(DS.Font.headline)
            LinearProgress(progress: viewModel.pendingProgress)
            Text(viewModel.pendingDetail)
                .font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !viewModel.isRunning {
                SecondaryButton(title: "Продолжить пересказ", action: viewModel.resume)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.m)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// Глава-карточка: в свёрнутом виде — номер, время чтения и название; по нажатию раскрывается текст.
private struct ChapterCard: View {
    let chapter: ChapterSummary
    let isExpanded: Bool
    let next: ChapterSummary?
    let onToggle: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: DS.Space.m) {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("Глава \(chapter.index) · ≈ \(readingMinutes) мин")
                            .font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                        Text(chapter.title)
                            .font(DS.Font.headline).foregroundColor(DS.Color.ink)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: DS.Space.s)
                    Image(systemName: "chevron.down")
                        .font(DS.Font.label)
                        .foregroundColor(DS.Color.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(DS.Motion.respecting(DS.Motion.tap), value: isExpanded)
                        .padding(.top, DS.Space.xs)
                }
                .padding(DS.Space.l)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Глава \(chapter.index). \(chapter.title)")
            .accessibilityValue(isExpanded ? "раскрыта" : "свёрнута")
            .accessibilityHint(isExpanded ? "Свернуть текст главы" : "Показать текст главы")

            if isExpanded {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    Rectangle().fill(DS.Color.line).frame(height: 1)
                    // Текст главы на тон спокойнее заголовка.
                    Text(chapter.text)
                        .font(DS.Font.body).foregroundColor(DS.Color.inkSoft)
                        .lineSpacing(4)
                    if let links = chapter.connections {
                        Label(links, systemImage: "link")
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.secondary)
                            .padding(DS.Space.m)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DS.Color.background)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                    }
                    if let next {
                        Button(action: onNext) {
                            HStack(spacing: DS.Space.xs) {
                                Text("Дальше: глава \(next.index)").font(DS.Font.label)
                                Image(systemName: "arrow.down").font(DS.Font.label)
                            }
                            .foregroundColor(DS.Color.ink)
                        }
                        .buttonStyle(PressScaleStyle())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding([.horizontal, .bottom], DS.Space.l)
                .transition(.opacity)
            }
        }
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous).stroke(DS.Color.line, lineWidth: 1))
    }

    private var readingMinutes: Int {
        max(1, Int((Double(chapter.text.split(separator: " ").count) / SummaryPreset.readingSpeed).rounded()))
    }
}

/// Предупреждение перед сводкой: экран размыт, по центру — полупрозрачная карточка.
private struct SpoilerGate: View {
    let onReveal: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            // Размытие всего экрана; тап мимо карточки — вернуться к главам.
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)

            VStack(spacing: DS.Space.l) {
                Image(systemName: "eye.slash")
                    .font(DS.Font.icon)
                    .foregroundColor(DS.Color.secondary)
                    .accessibilityHidden(true)
                VStack(spacing: DS.Space.s) {
                    Text("Краткое содержание всей книги")
                        .font(DS.Font.title)
                        .multilineTextAlignment(.center)
                    Text("Здесь сюжет целиком — с развязкой и главными поворотами. Если читаете впервые, лучше начать с глав.")
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                VStack(spacing: DS.Space.m) {
                    PrimaryButton(title: "Показать сводку", isFullWidth: true, action: onReveal)
                    TextLinkButton(title: "Читать по главам", action: onCancel)
                }
            }
            .padding(DS.Space.xl)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous).stroke(DS.Color.line, lineWidth: 1))
            .padding(.horizontal, DS.Space.xl)
            .accessibilityAddTraits(.isModal)
        }
    }
}
