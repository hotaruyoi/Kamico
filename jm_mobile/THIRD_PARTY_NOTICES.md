# Source attribution

## JMComic-qt

- Author/project: tonquer / https://github.com/tonquer/JMComic-qt
- Local source snapshot: `../JMComic-qt-main`, reported version v1.3.7, 2026-10-07.
- Protocol port references: `src/server/req.py`, `src/tools/tool.py`, `src/config/global_config.py`.
- Translation assets also adapt `translate/ui_en.ts`, `str_en.ts`, `ui_hk.ts`, and `str_hk.ts`, with additions for the Flutter interface.
- Original license: GNU Lesser General Public License v3; the supplied text is preserved in this project's `LICENSE`. The GPL v3 terms referenced by LGPL are included in `third_party/GPL-3.0.txt`.
- GPL text provenance: the unmodified GPL v3 license text distributed in the Free Software Foundation Europe REUSE tool's `reuse-6.2.0/LICENSES/GPL-3.0-or-later.txt` source archive on PyPI. REUSE code is not included.
- Changes: replacement Flutter UI, Dart HTTP/state/storage/download modules, Dart ports of request signing and image-strip restoration, Android/Windows runners. Original Qt source remains alongside this project.

The adapted implementation is distributed with the upstream LGPL v3 terms. Preserve the source and notices when redistributing this adaptation.

## JMComic-Crawler-Python

- Author: hect0x7, Copyright (c) 2023 hect0x7.
- Project: https://github.com/hect0x7/JMComic-Crawler-Python
- Version inspected: jmcomic 2.6.20, the original client's pinned dependency.
- Source inspected: `jmcomic/jm_config.py` and `jmcomic/jm_toolkit.py::JmCryptoTool.decode_resp_data` from the PyPI wheel.
- License: MIT, reproduced in `third_party/jmcomic.LICENSE`.
- Use: verification and Dart port of the response decryption protocol; no Python runtime is bundled.

## picacg-qt

- Author/project: tonquer / https://github.com/tonquer/picacg-qt
- Local source snapshot: `../picacg-qt-main`; the original Qt project is retained unchanged.
- Protocol references: `src/tools/tool.py`, `src/server/req.py`, `src/config/config.py`, `src/tools/book.py` and `src/tools/user.py`.
- Original license text is preserved verbatim in `third_party/picacg.LICENSE` and shown in the application's license registry.
- Changes: Dart implementation of PicACG request signing, authentication, pagination and media resolution, integrated into kamico's existing Flutter comic workflow. No Qt UI, Python runtime, chat, games, super-resolution or proxy stack is bundled.

## Flutter and Dart packages

Runtime dependency versions are recorded in `pubspec.lock`. Flutter's license registry includes package license notices, and the Settings screen exposes the license page. Additional notices above are registered by `lib/main.dart`.
