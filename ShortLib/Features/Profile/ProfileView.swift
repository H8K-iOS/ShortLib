import SwiftUI

struct ProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @AppStorage(Preferences.detailLevelKey) private var defaultLevel: String = DetailLevel.balanced.rawValue
    @AppStorage(Preferences.modelChoiceKey) private var modelChoice: String = LLMModelChoice.quality.rawValue
    @AppStorage(Preferences.languageKey) private var language: String = SummaryLanguage.russian.rawValue
    @FocusState private var isKeyFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                Text("Профиль").font(DS.Font.largeTitle).padding(.top, DS.Space.l)

                SettingsGroup(title: "Пересказ своими словами") {
                    Text("ShortLib использует Claude от Anthropic. Нужен ваш ключ API: запросы оплачиваются с вашего баланса в Anthropic, текст глав отправляется в Anthropic для обработки.")
                        .font(DS.Font.callout).foregroundColor(DS.Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if viewModel.hasKey {
                        HStack(spacing: DS.Space.m) {
                            StatusBadge(text: "Ключ сохранён", style: .success, systemImage: "checkmark")
                            Text(viewModel.maskedKey).font(DS.Font.caption.monospacedDigit()).foregroundColor(DS.Color.secondary)
                            Spacer()
                            TextLinkButton(title: "Удалить", action: viewModel.removeKey)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            SecureField("sk-ant-…", text: $viewModel.keyInput)
                                .font(DS.Font.body)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($isKeyFieldFocused)
                                .submitLabel(.done)
                                .onSubmit { isKeyFieldFocused = false }
                                .padding(.horizontal, DS.Space.m)
                                .padding(.vertical, 12)
                                .overlay(RoundedRectangle(cornerRadius: DS.Radius.s).stroke(DS.Color.secondary, lineWidth: 1))
                            PrimaryButton(title: viewModel.status == .checking ? "Проверяем ключ…" : "Проверить и сохранить",
                                          isFullWidth: true, isEnabled: viewModel.canSave) {
                                isKeyFieldFocused = false
                                viewModel.save()
                            }
                            Text("Где взять ключ: console.anthropic.com → Settings → API Keys → Create Key. Пополните баланс в разделе Billing.")
                                .font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if case .failed(let message) = viewModel.status {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(DS.Font.callout).foregroundColor(DS.Color.accent)
                    }
                }

                SettingsGroup(title: "Модель") {
                    ForEach(LLMModelChoice.allCases) { choice in
                        Button { modelChoice = choice.rawValue } label: {
                            HStack(spacing: DS.Space.m) {
                                Image(systemName: modelChoice == choice.rawValue ? "largecircle.fill.circle" : "circle")
                                    .font(DS.Font.headline)
                                    .foregroundColor(modelChoice == choice.rawValue ? DS.Color.accent : DS.Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(choice.title).font(DS.Font.headline)
                                    Text(choice.subtitle).font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                                }
                                Spacer()
                            }
                            .foregroundColor(DS.Color.ink)
                        }
                        .buttonStyle(.plain)
                    }
                }

                SettingsGroup(title: "Язык пересказа") {
                    FlowLayout {
                        ForEach(SummaryLanguage.allCases) { item in
                            FocusChip(title: item.title, isOn: language == item.rawValue) { language = item.rawValue }
                        }
                    }
                }

                SettingsGroup(title: "Детальность по умолчанию") {
                    FlowLayout {
                        ForEach(DetailLevel.allCases) { level in
                            FocusChip(title: level.title, isOn: defaultLevel == level.rawValue) {
                                defaultLevel = level.rawValue
                            }
                        }
                    }
                    Text("С этого уровня начинаются настройки каждого нового пересказа.")
                        .font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                }

                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("ShortLib").font(DS.Font.headline)
                    Text("Версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                }
                .padding(.bottom, DS.Space.xl)
            }
            .padding(.horizontal, DS.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Тап по тексту и пустым местам закрывает клавиатуру; кнопки и поле получают тап первыми.
            .contentShape(Rectangle())
            .onTapGesture { isKeyFieldFocused = false }
        }
        // Пустое место под содержимым и прокрутка тоже закрывают клавиатуру.
        .background(DS.Color.background.ignoresSafeArea().onTapGesture { isKeyFieldFocused = false })
        .scrollDismissesKeyboard(.interactively)
    }
}
