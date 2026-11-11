import SwiftUI

struct SummaryProgressView: View {
    @ObservedObject var viewModel: SummaryProgressViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CircleIconButton(systemImage: "chevron.left", accessibilityTitle: "Свернуть", action: viewModel.minimize)
                Spacer()
                StatusBadge(text: viewModel.badgeText, style: .accent)
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.s)

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("Читаем за вас").font(DS.Font.largeTitle)
                        Text("Можно свернуть экран: пересказ сохранится в библиотеке.")
                            .font(DS.Font.callout).foregroundColor(DS.Color.secondary)
                    }

                    ProgressRing(progress: viewModel.progress.fraction,
                                 title: viewModel.percentText,
                                 subtitle: viewModel.ringSubtitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Space.s)

                    VStack(spacing: 0) {
                        ForEach(SummaryProgress.Stage.allCases, id: \.self) { stage in
                            StepRow(title: stage.title, detail: viewModel.detail(of: stage), state: viewModel.state(of: stage))
                        }
                    }

                    if let error = viewModel.errorMessage {
                        VStack(alignment: .leading, spacing: DS.Space.m) {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(DS.Font.callout).foregroundColor(DS.Color.accent)
                            SecondaryButton(title: "Повторить", action: viewModel.start)
                        }
                        .padding(DS.Space.l)
                        .dsCard()
                    }
                }
                .padding(.horizontal, DS.Space.l)
                .padding(.bottom, DS.Space.xl)
            }

            FooterBar {
                TextLinkButton(title: "Отменить", action: viewModel.cancel)
            } trailing: {
                SecondaryButton(title: "Свернуть", action: viewModel.minimize)
            }
        }
    }
}

private struct StepRow: View {
    let title: String
    let detail: String
    let state: SummaryProgressViewModel.StepState

    var body: some View {
        HStack(spacing: DS.Space.m) {
            indicator.frame(width: 22, height: 22)
            Text(title).font(DS.Font.callout)
            Spacer()
            Text(detail).font(DS.Font.caption.monospacedDigit()).foregroundColor(DS.Color.secondary)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.Color.line).frame(height: 1) }
    }

    @ViewBuilder
    private var indicator: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(DS.Font.caption.weight(.bold))
                .foregroundColor(DS.Color.onAccent)
                .frame(width: 22, height: 22)
                .background(DS.Color.success)
                .clipShape(Circle())
        case .active:
            // Статичный индикатор вместо вращающегося спиннера — ноль работы на каждом кадре.
            Circle().stroke(DS.Color.accent, lineWidth: 2.5)
                .overlay(Circle().fill(DS.Color.accent).padding(6))
        case .waiting:
            Circle().stroke(DS.Color.line, lineWidth: 1.5)
        }
    }
}
