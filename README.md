# Mac Island

Плавающая панель у верхнего края экрана в духе Dynamic Island: музыка (Now Playing), история текста и картинок из буфера.

## Требования

- macOS 14+
- Для сборки через Xcode: Xcode 15+ и [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Без Xcode: достаточно Command Line Tools — скрипт `Scripts/build.sh` собирает `.app` через `swiftc`

## Сборка

### Вариант A — без Xcode (CLT)

```bash
chmod +x Scripts/build.sh
./Scripts/build.sh
open ".build/app/Mac Island.app"
```

### Вариант B — Xcode + xcodegen

```bash
brew install xcodegen
chmod +x Scripts/generate-project.sh
./Scripts/generate-project.sh
open MacIsland.xcodeproj
# или
xcodebuild -project MacIsland.xcodeproj -scheme "Mac Island" -configuration Release build
```

## Как пользоваться

1. Запусти приложение — в Dock его не будет (agent / `LSUIElement`), иконка в меню-баре.
2. Наведи курсор на зону notch / верхний центр экрана — панель раскроется.
3. Вкладки слева: **Музыка**, **Текст**, **Картинки**.
4. Клик по тексту/картинке в истории — копирует обратно в буфер.
5. В меню-баре: «Показать панель», «Показывать в Dock», «Выйти».

История буфера лежит в:

`~/Library/Application Support/MacIsland/`

## Права доступа

### Mouse / hover над notch

Используются `NSEvent.addGlobalMonitor` + local monitor для движения мыши.

- **Часто отдельное разрешение не нужно** для отслеживания позиции курсора.
- Если панель **не открывается**, пока фокус в другом приложении:
  1. **Системные настройки → Конфиденциальность и безопасность → Мониторинг ввода** (Input Monitoring)
  2. Добавь **Mac Island** и включи тумблер
  3. Перезапусти приложение

Accessibility обычно не требуется только для mouse moved; Input Monitoring — если система режет global monitor.

### Медиа (MediaRemote)

Now Playing читается через **private** `MediaRemote.framework` (динамическая загрузка `dlsym`).  
Это неофициальный API: может измениться в новых macOS. Если символы недоступны — вкладка музыки покажет пустое состояние, приложение не падает.

Управление play/pause/next/prev тоже через MediaRemote. Seek по скрабберу может не работать (приватный seek не всегда экспортируется).

## Ограничения

- Private MediaRemote — риск поломки после обновления macOS
- Без полного Xcode `xcodebuild` недоступен — используй `Scripts/build.sh`
- App Sandbox выключен (личная утилита: буфер + MediaRemote)
- Не App Store-ready без переписывания медиа-слоя на публичные API

## Структура

```
MacIsland/Sources/
  App/         — точка входа, состояние
  Panel/       — NSPanel, hover, blur
  UI/          — вкладки SwiftUI
  Media/       — MediaRemote
  Clipboard/   — polling буфера + диск
```

Bundle ID: `dev.nursat.MacIsland`
