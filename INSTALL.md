# Установка MegaWhisper

## Выбор формата

Используйте Flatpak по умолчанию. Он изолирует приложение, получает аудио через PulseAudio compatibility socket и использует desktop portals для секретов, глобальных клавиш и управляемой системной вставки. Прямой доступ к `pipewire-0`, input devices, домашнему каталогу или всей файловой системе приложению не выдается.

AppImage предназначен для систем без подходящего Flatpak runtime. Оба формата доступны только для x86_64 и не требуют root, правил udev, группы `input`, `uinput` или привилегированного input daemon.

## Flatpak

Установите подписанный `.flatpakref` последнего стабильного релиза:

```fish
flatpak install -y --user https://dxvsi.github.io/MegaWhisper/io.github.dxvsi.megawhisper.flatpakref
flatpak run io.github.dxvsi.megawhisper
```

Установка добавляет подписанный MegaWhisper remote для последующих обновлений. KDE runtime 6.11 загружается из Flathub при наличии сети.

Проверка permissions:

```fish
flatpak info --user --show-permissions io.github.dxvsi.megawhisper
```

Ожидаются Wayland, fallback X11, PulseAudio compatibility socket, DRI и network. Доступы `filesystem=host`, `filesystem=home`, `devices=all`, прямой `pipewire-0` и прямой доступ к input devices не требуются.

Обновление, просмотр доступных commits, rollback и удаление:

```fish
flatpak update -y --user io.github.dxvsi.megawhisper
flatpak remote-info --user --log megawhisper io.github.dxvsi.megawhisper
flatpak update -y --user --commit=COMMIT io.github.dxvsi.megawhisper
flatpak uninstall -y --user --delete-data io.github.dxvsi.megawhisper
```

Замените `COMMIT` значением из `flatpak remote-info --log`.

### Flatpak bundle

Файл `MegaWhisper-2.1.0-x86_64.flatpak` можно установить напрямую:

```fish
flatpak install -y --user ./MegaWhisper-2.1.0-x86_64.flatpak
```

Bundle содержит URL подписанного update remote. Сам KDE runtime в bundle не входит, но `RuntimeRepo` позволяет Flatpak загрузить его из Flathub. Для полностью автономной установки runtime необходимо доставить отдельно.

## AppImage

Скачайте AppImage из [последнего релиза](https://github.com/DXVSI/MegaWhisper/releases/latest), затем выполните:

```fish
chmod +x ./MegaWhisper-2.1.0-x86_64.AppImage
./MegaWhisper-2.1.0-x86_64.AppImage --appimage-updateinformation
env QT_QPA_PLATFORM=offscreen APPIMAGE_EXTRACT_AND_RUN=1 ./MegaWhisper-2.1.0-x86_64.AppImage --smoke-test
./MegaWhisper-2.1.0-x86_64.AppImage --install-desktop-integration
./MegaWhisper-2.1.0-x86_64.AppImage --check-desktop-integration
./MegaWhisper-2.1.0-x86_64.AppImage
```

Запуск кнопками работает без установки. Global Shortcuts portal и системная вставка требуют явной desktop integration в пользовательских XDG-каталогах. После перемещения AppImage повторите `--install-desktop-integration`, поскольку desktop entry привязан к точному абсолютному пути.

Удаление файлов desktop integration:

```fish
./MegaWhisper-2.1.0-x86_64.AppImage --remove-desktop-integration
```

Если FUSE недоступен, используйте:

```fish
env APPIMAGE_EXTRACT_AND_RUN=1 ./MegaWhisper-2.1.0-x86_64.AppImage
```

## Проверка подписей

MegaWhisper 2.1.0 и новее используют контракт `binary-v1` с десятью загружаемыми assets. Восемь payload assets перечислены в подписанном `SHA256SUMS`; сам `SHA256SUMS` и его подпись не могут входить в этот список из-за циклической зависимости.

Сначала получите полный fingerprint из `RELEASE_KEY_FINGERPRINT` в доверенном checkout публичного distribution-репозитория и независимо сверьте его с публикацией DXVSI. Ключ внутри Release сам по себе не является источником доверия к этому же Release.

```fish
set expected (string upper (string trim (cat ./RELEASE_KEY_FINGERPRINT)))
set actual (gpg --batch --with-colons --show-keys ./megawhisper-release-key.asc | awk -F: '$1 == "pub" { primary=1; next } $1 == "fpr" && primary { print toupper($10); exit }')
test "$actual" = "$expected"; or begin; echo "Fingerprint release key не совпадает" >&2; exit 1; end
gpg --import ./megawhisper-release-key.asc
gpg --verify ./SHA256SUMS.asc ./SHA256SUMS
sha256sum --check ./SHA256SUMS
```

Ожидаемый список payload assets:

- `MegaWhisper-2.1.0-x86_64.AppImage`;
- `MegaWhisper-2.1.0-x86_64.AppImage.zsync`;
- `MegaWhisper-2.1.0-x86_64.flatpak`;
- `io.github.dxvsi.megawhisper.flatpakref`;
- `io.github.dxvsi.megawhisper.flatpakrepo`;
- `MegaWhisper-2.1.0-third-party-compliance.tar.zst`;
- `MegaWhisper-2.1.0-recovery.tar.zst`;
- `megawhisper-release-key.asc`.

## Third-party compliance

`MegaWhisper-2.1.0-third-party-compliance.tar.zst` содержит binary SBOM, build provenance, notices, license inventories и corresponding source, обязательный для включенных сторонних компонентов. В нем нет исходного кода самого MegaWhisper.

Qt, GStreamer, `whisper.cpp`, AppImage runtime и другие сторонние компоненты сохраняют собственные лицензии. Canonical summary опубликован в [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

MegaWhisper 2.1.0 и новее являются proprietary software. Условия установки и использования официальных неизмененных бинарников находятся в [LICENSE](LICENSE). Публичный repository tag содержит только distribution-документы, сайт и verification tooling, но не исходный код приложения.

## Диагностика

### MegaWhisper уже запущен, но окна и tray нет

Сначала проверьте процесс:

```fish
flatpak ps | string match -r 'io\.github\.dxvsi\.megawhisper'
```

Если процесс остался после аварийного завершения desktop session, остановите только этот Flatpak instance и запустите приложение снова:

```fish
flatpak kill io.github.dxvsi.megawhisper
flatpak run io.github.dxvsi.megawhisper
```

### Горячая клавиша не зарегистрирована

Проверьте, что desktop portal запущен и комбинация записи не занята. Во Flatpak и AppImage согласие подтверждается системным диалогом Global Shortcuts portal. Не добавляйте пользователя в `input` и не меняйте permissions устройств.

### Подготовленный текст не вставился

MegaWhisper сначала записывает точный результат в clipboard. Системная вставка выполняется только выбранным режимом и может завершиться fail-closed при отказе portal, неготовом backend, занятости или timeout. В этом случае текст остается в clipboard для ручной вставки.

### Микрофон не виден

Проверьте устройство в системных настройках звука и заново выберите его в MegaWhisper. Приложение отслеживает hotplug и не должно хранить устаревший дескриптор устройства.

### Локальная модель не запускается

Откройте Model Manager, повторите verification и проверьте свободное место. Модель становится активной только после проверки SHA-256 и runtime smoke-test. При проблеме Vulkan приложение повторяет inference на CPU.
