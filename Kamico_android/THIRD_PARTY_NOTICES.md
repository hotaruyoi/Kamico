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
- Original license text is preserved verbatim in `third_party/picacg.LICENSE`. It is identical to `LICENSE`, so the application displays one shared LGPL text with both source attributions.
- Changes: Dart implementation of PicACG request signing, authentication, pagination and media resolution, integrated into kamico's existing Flutter comic workflow. No Qt UI, Python runtime, chat, games, super-resolution or proxy stack is bundled.

## ONNX Runtime

- Author/project: Microsoft / https://github.com/microsoft/onnxruntime
- Version bundled: 1.22.0, Android arm64-v8a and x86_64 prebuilt `libonnxruntime.so` from the Maven artifact `com.microsoft.onnxruntime:onnxruntime-android:1.22.0`.
- License: MIT. Header files used at build time: `onnxruntime_c_api.h` from the same artifact.
- Use: executes the local AI colorization model. The library is loaded only on 64-bit Android builds; other ABIs compile a stub that reports the feature as unsupported.

## AI colorization model (beta only)

- Source: the generator from https://github.com/qweasdd/manga-colorization-v2, converted to ONNX and statically quantized (int8 QDQ) for this project.
- **Licensing status: unresolved.** The upstream repository ships no license file and its requests for one are still unanswered, so the redistributed weights have no confirmed grant. This asset is therefore included only in the beta channel (`app.jmpic.jm_mobile.beta`) and must not be promoted to the public release channel until the upstream author states terms or the model is replaced.
- Changes: graph rewritten to replace `DepthToSpace` with equivalent shape/transpose operations and pinned to opset 15 so the ORT 1.22 kernel set can execute it, then converted to the `.ort` container format. Weights are unmodified apart from int8 quantization.

## stb

- Author: Sean Barrett and contributors / https://github.com/nothings/stb
- Files: `stb_image.h` 2.30 and `stb_image_write.h` 1.16, vendored under `android/app/src/main/cpp`.
- License: MIT or public domain (dual). Used for JPEG decode and encode inside the colorization pipeline.


## Flutter and Dart packages

Runtime dependency versions are recorded in `pubspec.lock`. Settings exposes notices for runtime packages, engine components and the adaptations above. Development-only dependency names and the duplicate root-package entry are omitted from the display; notices shared with runtime packages are retained. The full generated NOTICES asset remains bundled. Application notices are registered by `lib/main.dart` via `lib/data/app_licenses.dart`.
