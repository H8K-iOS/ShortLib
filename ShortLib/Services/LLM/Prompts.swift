import Foundation

/// Все промпты пересказа в одном месте. Модель отвечает в XML-тегах — их проще и надёжнее разбирать, чем JSON.
enum Prompts {

    // MARK: - System

    static func system(preset: SummaryPreset, bookTitle: String, author: String) -> String {
        let quotesRule = preset.focus.contains(.quotes)
            ? "Можно вставить 1–2 короткие яркие цитаты в «ёлочках»."
            : "Цитаты не используй."
        let spoilerRule = preset.noSpoilers
            ? "Спойлеры запрещены: ты знаешь книгу только до текущей главы и не делаешь предположений о будущем."
            : "Спойлеры разрешены."
        return """
        Ты — литературный редактор. Ты пишешь пересказы книги «\(bookTitle)» (\(author)) для читателя, \
        который хочет понять историю, не читая оригинал целиком. Пересказ — это не выборка фрагментов, \
        а осмысленный рассказ своими словами о том, что произошло, почему и что это значит.

        Как писать:
        - Своими словами, связным текстом по абзацам, в настоящем времени, от третьего лица.
        - Порядок: сначала где, когда и кто действует; затем события по порядку; в конце — чем глава заканчивается.
        - Не только что произошло, но и почему и к чему это ведёт: мотивы героев, причины и следствия.
        - Отделяй главное от второстепенного: ключевые события, идеи и аргументы раскрывай, \
        второстепенное — одной фразой или опускай.
        - Сохраняй замысел автора: если на споре или размышлениях героев держится глава, передай суть их аргументов \
        и позицию автора.
        - Передавай интонацию автора выбором слов — иронию, сатиру, напряжение, лиризм, — но не копируй предложения \
        оригинала. \(quotesRule)
        - Диалоги передавай косвенной речью: кто, что и зачем сказал.
        - Каждое предложение добавляет новое. Не повторяй одну мысль и одни и те же эпитеты.
        - Только факты из текста: ничего не выдумывай и не приписывай детали не тем персонажам.
        - Не начинай со штампов вроде «В этой главе рассказывается…» и не заканчивай фразой «Таким образом…».
        - Если возвращаются персонажи, предметы или загадки из прошлых глав, коротко напомни, кто это и откуда.
        - \(language(preset.language))

        Подробность: \(detail(preset.level)).
        Акцент: \(focus(preset.focus)).
        \(spoilerRule)
        """
    }

    // MARK: - Chapter

    static func chapter(index: Int, title: String, text: String, isNotes: Bool, level: DetailLevel,
                        memory: String, previousSummary: String, targetWords: Int) -> String {
        let memoryText = memory.isEmpty ? "Это начало книги, памяти пока нет." : memory
        let previousText = previousSummary.isEmpty ? "—" : previousSummary
        let notesHint = isNotes ? "Глава длинная, ниже даны подробные заметки по её частям по порядку.\n" : ""
        let meaningRule = level == .detailed
            ? " Последний абзац — 1–3 предложения о значении главы для всей книги: что изменилось, какой вопрос поставлен."
            : " Отдельный абзац-вывод о значении главы не пиши."
        return """
        <story_memory>
        \(memoryText)
        </story_memory>

        <previous_chapter_summary>
        \(previousText)
        </previous_chapter_summary>

        <chapter number="\(index)" title="\(escape(title))">
        \(notesHint)\(text)
        </chapter>

        Задание:
        1. Разбери главу для себя (читатель этого не увидит), не больше 120 слов, кратко по пунктам: \
        главное событие; второстепенное, что можно сжать; причины и следствия; конфликт или идея главы; \
        тон автора; чем глава заканчивается и что осталось открытым.
        2. По этому разбору перескажи главу \(index) примерно в \(targetWords) словах (допустимо ±15%).\(meaningRule)
        3. Обнови память сюжета с учётом этой главы: персонажи (имя — кто это, отношения, что с ним сейчас), \
        открытые сюжетные линии и загадки, важные факты о мире. Удаляй устаревшее. Не больше 350 слов, списком.

        Ответ строго в формате:
        <analysis>разбор</analysis>
        <summary>пересказ главы</summary>
        <memory>обновлённая память сюжета</memory>
        """
    }

    /// Заметки по части длинной главы.
    static func chunk(part: Int, of total: Int, chapterTitle: String, text: String, memory: String, targetWords: Int) -> String {
        let memoryText = memory.isEmpty ? "—" : memory
        return """
        <story_memory>
        \(memoryText)
        </story_memory>

        <chapter_part chapter="\(chapterTitle)" part="\(part)" of="\(total)">
        \(text)
        </chapter_part>

        Сделай подробные заметки по этой части главы: все значимые события по порядку, кто участвует, \
        что узнаём нового. Примерно \(targetWords) слов.

        Ответ строго в формате:
        <notes>заметки</notes>
        """
    }

    // MARK: - Connections (второй проход, только со спойлерами)

    static func connections(index: Int, summary: String, earlier: [(Int, String)], later: [(Int, String)]) -> String {
        func block(_ items: [(Int, String)]) -> String {
            items.isEmpty ? "—" : items.map { "Глава \($0.0): \($0.1)" }.joined(separator: "\n\n")
        }
        return """
        <earlier_chapters>
        \(block(earlier))
        </earlier_chapters>

        <current_chapter number="\(index)">
        \(summary)
        </current_chapter>

        <later_chapters>
        \(block(later))
        </later_chapters>

        Найди важные связи текущей главы с другими: что здесь продолжает прошлые события, \
        что подготавливает будущие, какие загадки или намёки раскроются позже и где. \
        Укажи номера глав. 1–3 коротких предложения. Если значимых связей нет, ответь «нет».

        Ответ строго в формате:
        <links>связи</links>
        """
    }

    // MARK: - Overview

    static func arc(fromChapter: Int, toChapter: Int, summaries: String, targetWords: Int) -> String {
        """
        <chapters from="\(fromChapter)" to="\(toChapter)">
        \(summaries)
        </chapters>

        Объедини пересказы этих глав в связный пересказ сюжетной арки примерно в \(targetWords) слов. \
        Сохрани главные события, повороты и изменения героев.

        Ответ строго в формате:
        <arc>пересказ арки</arc>
        """
    }

    static func overview(material: String, memory: String, targetWords: Int) -> String {
        """
        <story_memory>
        \(memory)
        </story_memory>

        <material>
        \(material)
        </material>

        Задание:
        1. Напиши общий пересказ прочитанной части книги примерно в \(targetWords) слов: завязка, \
        главные повороты, к чему пришли герои, какие вопросы остаются открытыми.
        2. Составь список главных персонажей (до 12): имя и одно-два предложения о том, кто это и какова его роль.

        Ответ строго в формате:
        <overview>общий пересказ</overview>
        <characters>
        Имя — описание
        Имя — описание
        </characters>
        """
    }

    // MARK: - Fragments

    /// Кавычки и скобки в названии главы не должны ломать XML-атрибут.
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func detail(_ level: DetailLevel) -> String {
        switch level {
        case .brief:
            return "кратко — главные события главы, их причины и последствия; второстепенные сцены опускай"
        case .balanced:
            return "сбалансированно — основные события по порядку, мотивы героев и суть важных разговоров"
        case .detailed:
            return "подробно — все значимые сцены по порядку, аргументы героев в ключевых спорах, атмосфера, "
                + "детали мира и вывод о значении главы"
        }
    }

    private static func focus(_ focus: Set<SummaryFocus>) -> String {
        var parts: [String] = []
        if focus.contains(.plot) { parts.append("события и повороты сюжета") }
        if focus.contains(.characters) { parts.append("персонажи, их мотивы и отношения") }
        if focus.contains(.world) { parts.append("устройство мира, магия, правила, места") }
        if focus.contains(.quotes) { parts.append("характерные фразы героев") }
        return parts.isEmpty ? "сюжет" : parts.joined(separator: "; ")
    }

    private static func language(_ language: SummaryLanguage) -> String {
        switch language {
        case .russian: return "Пиши на русском языке, даже если оригинал на другом. Имена передавай общепринятой русской транскрипцией."
        case .original: return "Пиши на языке оригинала книги."
        }
    }
}

/// Разбор ответа модели по тегам.
enum TagParser {
    static func value(_ tag: String, in text: String) -> String? {
        if let open = text.range(of: "<\(tag)>") {
            let rest = text[open.upperBound...]
            let body = rest.range(of: "</\(tag)>").map { rest[..<$0.lowerBound] } ?? rest
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    static func characters(in text: String) -> [CharacterNote] {
        guard let block = value("characters", in: text) else { return [] }
        return block.split(separator: "\n").compactMap { line in
            let clean = line.trimmingCharacters(in: CharacterSet(charactersIn: " -•*\t"))
            let parts = clean.components(separatedBy: " — ")
            guard parts.count >= 2 else {
                let alt = clean.components(separatedBy: " - ")
                guard alt.count >= 2 else { return nil }
                return CharacterNote(name: alt[0], note: alt.dropFirst().joined(separator: " - "))
            }
            return CharacterNote(name: parts[0], note: parts.dropFirst().joined(separator: " — "))
        }
    }
}
