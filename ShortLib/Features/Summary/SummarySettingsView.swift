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
                    HStack(alignment: .top, spacing: DS.Space.m) {
                        Image(systemName: viewModel.usesLanguageModel ? "sparkles" : "text.quote")
                            .font(DS.Font.headline)
                            .foregroundColor(viewModel.usesLanguageModel ? DS.Color.accent : DS.Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.engineTitle).font(DS.Font.headline)
                            Text(viewModel.engineDetail).font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Space.m)
                    .background(DS.Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))

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
                        HStack(spacing: DS.Space.s) {
                            FocusChip(title: "Все \(viewModel.chapterCount)", isOn: viewModel.isAllChapters,
                                      action: viewModel.selectAllChapters)
                            Spacer()
                            Stepper(value: $viewModel.lastChapter, in: 1...max(1, viewModel.chapterCount)) {
                                Text("До главы \(viewModel.lastChapter)")
                                    .font(DS.Font.headline.monospacedDigit())
                            }
                            .fixedSize()
                        }
                    }
                }
                .padding(DS.Space.l)
            }

            FooterBar {
                TextLinkButton(title: "Сбросить", action: viewModel.reset)
            } trailing: {
                PrimaryButton(title: "Создать пересказ", action: viewModel.create)
            }
        }
    }
}
