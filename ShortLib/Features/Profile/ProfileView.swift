import SwiftUI

struct ProfileView: View {
    @AppStorage(Preferences.detailLevelKey) private var defaultLevel: String = DetailLevel.balanced.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                Text("Профиль").font(DS.Font.largeTitle).padding(.top, DS.Space.l)

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
            }
            .padding(.horizontal, DS.Space.l)
        }
    }
}
