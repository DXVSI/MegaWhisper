# Установка MegaWhisper

## Выбор формата

Используйте Flatpak по умолчанию. Он не изменяет read-only базовую систему, изолирует приложение, получает аудио через sandbox-разрешение PulseAudio и использует системные portals для секретов и глобальных клавиш. На современных системах этот socket обычно обслуживает совместимый слой PipeWire Pulse. Прямой доступ к `pipewire-0` приложению не выдается. Чистая установка работает только через clipboard. Пользователь может явно выбрать beta-вставку после второй комбинации либо beta-автовставку сразу после транскрибации. В обоих режимах точный текст сначала остается в clipboard, а профиль по умолчанию равен `Shift+Insert`. Совместимость конкретного дистрибутива и desktop portal должна быть подтверждена ручной матрицей перед стабильным релизом.

AppImage предназначен для систем без подходящего Flatpak runtime. Нативная сборка нужна разработчикам и сопровождающим дистрибутивов.

Ни один вариант не требует root-доступа для работы приложения, правил udev, группы `input`, `uinput` или input-daemon.

## Flatpak repository

После публикации стабильного релиза скачайте из GitHub Release:

- `io.github.dxvsi.megawhisper.flatpakref`;
- `megawhisper-release-key.asc` для ручной сверки подписи.

Полный fingerprint ключа сначала получите из файла `RELEASE_KEY_FINGERPRINT` в доверенном checkout репозитория и сверьте с независимой публикацией автора DXVSI. Ключ из Release нельзя считать собственным источником доверия для самого Release.

Установка:

```fish
flatpak install -y --user ./io.github.dxvsi.megawhisper.flatpakref
flatpak run io.github.dxvsi.megawhisper
```

Файлы `flatpak/*.in` в checkout являются шаблонами release pipeline с незаполненными URL и GPG key. Их нельзя открывать, устанавливать или просто переименовывать. Готовые подписанные `.flatpakref` и `.flatpakrepo` публикуются только как artifacts GitHub Release.

Для сборки и установки текущего checkout используйте локальный installer:

```fish
scripts/install-local-flatpak.sh 2.0.0
flatpak run io.github.dxvsi.megawhisper.Devel
```

Installer создает изолированную временную Flatpak build-среду, подключает в ней Flathub, собирает bundle с app ID `io.github.dxvsi.megawhisper.Devel`, затем устанавливает или обновляет development-приложение только для текущего пользователя и проверяет точную package identity. Bundle содержит `RuntimeRepo` Flathub. Если на хосте нет KDE runtime, Flatpak может добавить официальный Flathub как user remote и загрузить runtime для текущего пользователя. Stable ID `io.github.dxvsi.megawhisper` не изменяется.

Проверка permissions:

```fish
flatpak info --user --show-permissions io.github.dxvsi.megawhisper
```

Ожидаются Wayland, fallback X11, PulseAudio compatibility socket, DRI и network. Доступы `filesystem=host`, `filesystem=home`, `devices=all`, прямой `pipewire-0` и прямой доступ к input devices не требуются.

Обновление, rollback и удаление:

```fish
flatpak update -y --user io.github.dxvsi.megawhisper
flatpak remote-info --user --log megawhisper io.github.dxvsi.megawhisper
flatpak update -y --user --commit=COMMIT io.github.dxvsi.megawhisper
flatpak uninstall -y --user --delete-data io.github.dxvsi.megawhisper
```

`COMMIT` замените на значение из `flatpak remote-info --log`.

Восстановление опубликованного полного Pages state выполняется ручной операцией `restore-flatpak-pages` только из защищенной ветки `production`. Обычно указывается ID успешного release run; завершенный non-success run допустим только тогда, когда точный stable Release уже опубликован и разрешается в подписанный source SHA. Проверяются подписи, pinned fingerprint, SHA-256, сайт, OSTree integrity и точный commit. Для первого неудачного выпуска без опубликованного stable Release предусмотрена отдельная production-only операция `restore-first-release-rollback`, которая принимает failed run и разворачивает подписанный repository без application refs вместе с сайтом без активной установки. Это новый полный Pages deployment, а не атомарный rollback. Он не понижает уже установленный Flatpak, поэтому клиентский downgrade выполняется отдельно командой с `--commit=COMMIT`.

## Flatpak bundle

Bundle удобен для локальной онлайн-установки приложения даже на чистой системе: в нем есть `RuntimeRepo` для загрузки KDE runtime 6.11 из Flathub. Пока Flathub предоставляет Qt 6.11.1, Flatpak содержит полный app-local Qt Multimedia с точным upstream-исправлением QTBUG-147011. Перед release проверяются путь загруженной библиотеки, GStreamer plugin, active input/output lifecycle через production PulseAudio compatibility backend и отдельный teardown через временно разрешенный direct PipeWire без version-based skip:

```fish
flatpak install -y --user ./MegaWhisper-2.0.0-x86_64.flatpak
```

Подписанный bundle из GitHub Release содержит URL подписанного репозитория и при установке добавляет remote для дальнейших обновлений. Сам runtime в bundle не входит, но `RuntimeRepo` позволяет Flatpak загрузить его при наличии сети. Для полностью автономной офлайн-установки необходимо заранее отдельно доставить `org.kde.Platform` 6.11. `.flatpakref` остается предпочтительным способом первоначальной установки, потому что он меньше и явно описывает канал.

## AppImage

```fish
chmod +x ./MegaWhisper-2.0.0-x86_64.AppImage
./MegaWhisper-2.0.0-x86_64.AppImage --appimage-updateinformation
env QT_QPA_PLATFORM=offscreen APPIMAGE_EXTRACT_AND_RUN=1 ./MegaWhisper-2.0.0-x86_64.AppImage --smoke-test
./MegaWhisper-2.0.0-x86_64.AppImage --install-desktop-integration
./MegaWhisper-2.0.0-x86_64.AppImage --check-desktop-integration
./MegaWhisper-2.0.0-x86_64.AppImage
```

Переносимый запуск и работа кнопками возможны без установки. Global Shortcuts portal и системная вставка требуют явной desktop integration в пользовательских XDG-каталогах. Если AppImage перемещен, повторите `--install-desktop-integration`, поскольку desktop entry привязан к точному абсолютному пути. Для удаления созданных приложением desktop entry, иконки и принадлежащего ему autostart entry выполните:

```fish
./MegaWhisper-2.0.0-x86_64.AppImage --remove-desktop-integration
```

Installer не перезаписывает и не удаляет файлы, принадлежность которых MegaWhisper подтвердить не может.

Если FUSE недоступен, runtime может запускаться через `APPIMAGE_EXTRACT_AND_RUN=1`:

```fish
env APPIMAGE_EXTRACT_AND_RUN=1 ./MegaWhisper-2.0.0-x86_64.AppImage
```

AppImage использует только Qt GStreamer multimedia backend для `QAudioSource` и `QAudioSink` и содержит собственные scanner и необходимые plugins. FLAC истории декодируется напрямую через libFLAC без `QMediaPlayer/GstPlay`. Qt FFmpeg и OpenH264 не включаются. Графические библиотеки OpenGL, fontconfig, FreeType, HarfBuzz, X11 и XCB предоставляет обычное desktop-окружение дистрибутива. Release также содержит license inventory, точные source RPM для содержимого SquashFS, закрепленные исходники type2-runtime, libfuse и squashfuse, а также upstream-архивы permissive runtime-компонентов. Upstream type2-runtime использует mutable Alpine repository, поэтому для musl, zstd, zlib и mimalloc не заявляется доказанная побайтовая воспроизводимость Alpine build inputs.

Текущий предварительный default локального режима равен Balanced `whisper-large-v3-turbo-q5_0`. Его нельзя трактовать как доказанно лучшую модель до завершения WER/CER, latency, RAM и VRAM матрицы.

## Проверка подписей

До импорта сравните полный fingerprint публичного ключа с закрепленным значением:

```fish
set expected (string upper (string trim (cat ./RELEASE_KEY_FINGERPRINT)))
set actual (gpg --batch --with-colons --show-keys ./megawhisper-release-key.asc | awk -F: '$1 == "pub" { primary=1; next } $1 == "fpr" && primary { print toupper($10); exit }')
test "$actual" = "$expected"; or begin; echo "Fingerprint release key не совпадает" >&2; exit 1; end
```

Только после успешной сверки импортируйте ключ и проверьте общий список хешей:

```fish
gpg --import ./megawhisper-release-key.asc
gpg --verify ./SHA256SUMS.asc ./SHA256SUMS
sha256sum --check ./SHA256SUMS
```

Проверка отдельного файла:

```fish
gpg --verify ./MegaWhisper-2.0.0-x86_64.AppImage.asc ./MegaWhisper-2.0.0-x86_64.AppImage
```

GitHub Release также содержит SPDX SBOM и подписанный `MegaWhisper-VERSION-build-provenance.json`. AppImage SBOM отдельно описывает исполняемый type2 runtime перед SquashFS и его статические зависимости.

Для проверки исходников Release содержит `MegaWhisper-VERSION-source.tar.zst`, созданный из того же очищенного orphan snapshot, на который указывает публичный tag. Snapshot содержит expanded `whisper.cpp`, `SOURCE-GRAPH.txt`, Qt Multimedia patch и не содержит приватную Git history или внутренние файлы. Отдельно публикуются официальный Qt Multimedia source tarball, AppImage runtime source, использованные source RPM и source-component SPDX.

## Сборка из исходников

### Fedora

```fish
sudo dnf install -y appstream cmake desktop-file-utils file flac-devel gcc-c++ git glslc libei-devel libsamplerate-devel libxkbcommon-devel make ninja-build qt6-qtbase-devel qt6-qtmultimedia-devel qt6-qttools-devel qtkeychain-qt6-devel vulkan-loader-devel
git submodule update --init --recursive
set -x SOURCE_DATE_EPOCH (git log -1 --format=%ct)
scripts/ci/build-native.sh 2.0.0 1 development
scripts/install-development-desktop.sh install
scripts/install-development-desktop.sh check
```

Native development build атомарно сохраняет fingerprint фактических входов и отдельную identity `io.github.dxvsi.megawhisper.NativeDevel`. Она намеренно отличается от development Flatpak `io.github.dxvsi.megawhisper.Devel`, поэтому меню приложений не подменяет один вариант другим. `run-megawhisper.sh` сверяет manifest перед каждым запуском и завершает работу с кодом `66`, если он отсутствует, поврежден, не совпадает с бинарным файлом или исходники изменились. Smoke-команды desktop integration не требуют. Для обычного запуска нужен созданный выше development desktop entry. Удалить его можно командой `scripts/install-development-desktop.sh uninstall`; launcher не выполняет скрытую пересборку или установку.

Установка release-конфигурации в отдельный staging root без изменения системы:

```fish
set stage (mktemp -d)
scripts/ci/build-native.sh 2.0.0 1 native $stage
find $stage -maxdepth 6 -type f
```

Build script выполняет staging install до восстановления tracked qmake-файлов. Для системного пакета сопровождающий использует тот же явный staging-контракт, а конечным пользователям рекомендуется Flatpak.

### Проверка сборки

```fish
env QT_QPA_PLATFORM=offscreen ./run-megawhisper.sh --smoke-test
env QT_QPA_PLATFORM=offscreen ./run-megawhisper.sh --ui-smoke-test
env QT_QPA_PLATFORM=offscreen ./run-megawhisper.sh --media-smoke-test
desktop-file-validate resources/io.github.dxvsi.megawhisper.desktop
appstreamcli validate --pedantic resources/io.github.dxvsi.megawhisper.metainfo.xml
```

## Диагностика

### Горячая клавиша не зарегистрирована

Проверьте, что desktop portal запущен и комбинация записи не занята. В режиме вставки с подтверждением обе комбинации должны различаться, а вторая комбинация должна содержать модификатор. В clipboard и automatic режимах комбинация подтверждения отключена и не регистрируется. Во Flatpak, AppImage и нативной сборке согласие подтверждается системным диалогом Global Shortcuts portal. Не добавляйте пользователя в `input` и не меняйте permissions устройств.

### Подготовленный текст не вставился

На чистой установке MegaWhisper только копирует точный текст. В beta-режиме с подтверждением переведите фокус в нужное поле и нажмите отдельную глобальную комбинацию. В automatic beta mode приложение выполняет ровно одну попытку сразу после успешной транскрибации в окне, активном в этот момент, без второй комбинации и без попытки восстановить прежний фокус. При первом включении подтвердите запрос Remote Desktop portal. Профиль по умолчанию отправляет `Shift+Insert` только после release boundary и проверки нейтрального состояния модификаторов; также доступны `Ctrl+V`, `Ctrl+Shift+V` и одна пользовательская комбинация. Состояние `attempted` не доказывает, что поле приняло текст. При неизвестном или ненейтральном состоянии модификаторов, отказе или отзыве разрешения, неготовом EIS, занятости либо timeout текст остается в clipboard, а отложенная повторная попытка не создается.

### Микрофон не виден

Проверьте устройство в системных настройках звука, затем заново выберите его в MegaWhisper. Приложение отслеживает hotplug и не хранит устаревший дескриптор устройства.

### Локальная модель не запускается

Откройте Model Manager, повторите verification и проверьте свободное место. Модель становится активной только после проверки SHA-256 и runtime smoke-test. При проблеме Vulkan приложение автоматически повторяет inference на CPU.

### Retry недоступен

Retry доступен, пока исходный FLAC остается в управляемом хранилище. Политика `session` использует приватный managed FLAC только до завершения приложения. После аварийного завершения startup recovery обрабатывает остатки oldest-first в пределах 3 секунд, 8 файлов и 64 MiB, поэтому очень большой backlog может потребовать нескольких запусков. Quarantine также ограничен 8 файлами и 64 MiB. Файлы `.deleting-*` восстанавливаются только при точном совпадении SHA-256 и размера, а symlink или collision обрабатываются fail-closed. Политика `text` держит ограниченную временную копию для Retry не более десяти минут и никогда не восстанавливает ее после перезапуска.
