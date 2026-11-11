#!/bin/sh
# Проверка гайдлайнов ShortLib. Запускается как Build Phase и выдаёт warning в Xcode.
#  1. Цвета только из DS.Color   2. Шрифт только из DS.Font   3. Только лёгкие анимации из DS.Motion
# Файлы дизайн-системы (ShortLib/DesignSystem/DS.swift) — единственное место, где это разрешено.

ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}/ShortLib"
STATUS=0

check() {
  pattern="$1"; message="$2"
  grep -rnE "$pattern" "$ROOT" --include='*.swift' | grep -v '/DesignSystem/DS.swift' | while IFS= read -r line; do
    file=$(echo "$line" | cut -d: -f1); num=$(echo "$line" | cut -d: -f2)
    echo "$file:$num: warning: [Guidelines] $message"
  done
}

check 'Color\(red:|UIColor\(red:|Color\(hex|#colorLiteral|\.(white|black|red|blue|green|gray|orange|pink|purple|yellow)\b[^.]' \
      'Используйте цвет из DS.Color вместо литерала'
check '\.font\(\.system|Font\.custom|UIFont\(name:|\.font\(\.(title|body|headline|caption|footnote|callout|subheadline|largeTitle)' \
      'Используйте шрифт из DS.Font'
check 'repeatForever|\.spring\(|interpolatingSpring|withAnimation[[:space:]]*\{|\.animation\(\.(easeIn|easeInOut|linear|default|spring)' \
      'Используйте лёгкую анимацию из DS.Motion (без бесконечных циклов и пружин)'

exit $STATUS
