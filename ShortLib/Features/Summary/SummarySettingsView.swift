import SwiftUI

struct SummarySettingsView: View {
    @ObservedObject var viewModel: SummarySettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Настройки пересказа").font(DS.Font.headline)
                HStack {
                    Button(action: viewModel.close) {
                        Image(systemName: "xmark").font(DS.Font.headline).foregroundColor(DS.Color.ink)
                    }
                    .accessibilityLabel("Закрыть")
                    Spacer()
                }
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.top, DS.Space.xl)
            .padding(.bottom, DS.Space.m)
            Rectangle().fill(DS.Color.line).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    if viewModel.isLimitReached {
                        limitReachedCard
                    }
                    engineCard

                    SettingsGroup(title: "Детальность") {
                        DetailLevelPicker(level: $viewModel.level, ratio: $viewModel.ratio)
                        Text(viewModel.estimateText).font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                    }

                    SettingsGroup(title: "На чём сосредоточиться") {
                        FlowLayout {
                            ForEach(SummaryFocus.allCases) { item in
                                FocusChip(title: item.title, isOn: viewModel.focus.contains(item)) {
                                    viewModel.toggle(item)
                                }
                            }
                        }
                    }

                    SettingsGroup(title: "Спойлеры") {
                        Toggle(isOn: $viewModel.noSpoilers) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Без спойлеров").font(DS.Font.headline)
                                Text(viewModel.spoilerDetail)
                                    .font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                            }
                        }
                        .tint(DS.Color.ink)
                    }

                    SettingsGroup(title: "Главы") {
                        chapterPicker
                    }
                }
                .padding(DS.Space.l)
            }

            FooterBar {
                TextLinkButton(title: "Сбросить", action: viewModel.reset)
            } trailing: {
                // Акцент один на экран: если лимит исчерпан, главная кнопка — «Добавить свой ключ» в карточке.
                if viewModel.isLimitReached {
                    SecondaryButton(title: viewModel.createTitle, action: viewModel.create)
                } else {
                    PrimaryButton(title: viewModel.createTitle, action: viewModel.create)
                }
            }
        }
    }

    // MARK: - Блоки

    /// Чем будет сделан пересказ; в бесплатном режиме — с остатком глав.
    private var engineCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(alignment: .top, spacing: DS.Space.m) {
                Image(systemName: viewModel.usesLanguageModel ? "sparkles" : "text.quote")
                    .font(DS.Font.headline)
                    .foregroundColor(viewModel.usesLanguageModel ? DS.Color.accent : DS.Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.engineTitle).font(DS.Font.headline)
                    Text(viewModel.engineDetail).font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let left = viewModel.freeChaptersLeft {
                QuotaMeter(left: left, total: SummarySettingsViewModel.freeChapterLimit)
            }
            if viewModel.showsAddKeyLink {
                TextLinkButton(title: "Добавить ключ", action: viewModel.addKey)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.m)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
    }

    private var limitReachedCard: some View {
        NoticeCard(systemImage: "book.closed",
                   title: "Бесплатные главы закончились",
                   message: "Вы пересказали \(SummarySettingsViewModel.freeChapterLimit) из \(SummarySettingsViewModel.freeChapterLimit) бесплатных глав. Чтобы продолжить своими словами, добавьте ключ Claude API.") {
            PrimaryButton(title: "Добавить свой ключ", isFullWidth: true, action: viewModel.addKey)
            Text("Подписка появится скоро")
                .font(DS.Font.caption).foregroundColor(DS.Color.secondary)
        }
    }

    private var chapterPicker: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: DS.Space.s) {
                if viewModel.isChapterLimited {
                    // Вся книга — только со своим ключом: показываем это, но не даём выбрать.
                    StatusBadge(text: "Все \(viewModel.chapterCount)", systemImage: "lock")
                        .overlay(Capsule().stroke(DS.Color.line, lineWidth: 1))
                        .accessibilityLabel("Все \(viewModel.chapterCount) глав — со своим ключом")
                } else {
                    FocusChip(title: "Все \(viewModel.chapterCount)", isOn: viewModel.isAllChapters,
                              action: viewModel.selectAllChapters)
                }
                Spacer()
                Stepper(value: $viewModel.lastChapter, in: 1...viewModel.maxSelectableChapter) {
                    Text("До главы \(viewModel.lastChapter)")
                        .font(DS.Font.headline.monospacedDigit())
                }
                .fixedSize()
            }
            if let hint = viewModel.chapterHint {
                Text(hint).font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
