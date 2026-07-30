# Возрастной рейтинг (#90)

Ответы на анкету App Store Connect → **Age Rating**. Приложение — утилита сетевой диагностики,
без контента 17+. Ожидаемый итог: **4+**.

## Ответы на анкету (все — «None», если не отмечено)

| Вопрос | Ответ |
|---|---|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Sexual Content or Nudity | None |
| Profanity or Crude Humor | None |
| Alcohol, Tobacco, or Drug Use or References | None |
| Mature/Suggestive Themes | None |
| Horror/Fear Themes | None |
| Medical/Treatment Information | None |
| Gambling (simulated) | None |
| Contests | None |
| **Unrestricted Web Access** | **No** |
| **Age Assurance / Kids Category** | не заявляем Kids Category |

## Тонкие места

- **Unrestricted Web Access = No.** Это про встроенный браузер общего назначения (как Safari внутри
  приложения). У CheckNet его нет: инструменты обращаются к конкретным хостам по команде и показывают
  результат проверки (заголовки, статус, страница-заглушка при детекте блокировки) — это не
  веб-сёрфинг. Если бы мы отдавали пользователю произвольную навигацию по вебу — было бы Yes.
- **Kids Category — не заявляем.** Приложение не для детей; заявление Kids Category навесило бы
  жёсткие требования (никаких внешних ссылок и т. п.), которые нам не подходят (есть ссылки на
  bgp.tools/GitHub и т. д.).
- Итоговый рейтинг Apple посчитает сам из ответов; при всех «None»/«No» это **4+**.

## Что нажать

1. ASC → приложение → Age Rating → Edit → проставить значения из таблицы → Save.
2. Убедиться, что рейтинг показывается как 4+ (или Apple-эквивалент по регионам).
