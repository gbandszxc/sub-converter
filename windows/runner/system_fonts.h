#ifndef RUNNER_SYSTEM_FONTS_H_
#define RUNNER_SYSTEM_FONTS_H_

#include <string>
#include <vector>

namespace flutter {
class BinaryMessenger;
}

namespace system_fonts {

// Answers the Dart side's "sub_converter/fonts" method channel:
//   installedFontFamilies -> list of family names (UTF-8)
//   defaultFontFamily     -> the system UI font family, or the curated
//                            fallback when it cannot be queried
void RegisterChannel(flutter::BinaryMessenger* messenger);

// Every installed font family name as DirectWrite spells it (localized to the
// user's locale), sorted case-insensitively. The DirectWrite collection is the
// source on purpose: it is the same matching the Flutter engine does, so
// weight-split GDI names ("Microsoft YaHei UI Light") that DirectWrite cannot
// resolve as families never reach the picker.
std::vector<std::string> InstalledFontFamilies();

// The family the shell uses for its own UI text (NONCLIENTMETRICS
// lfMessageFont): "Microsoft YaHei UI" on Chinese Windows, "Segoe UI" on
// English Windows, "Meiryo UI" on Japanese Windows, and so on. Falls back to
// "Microsoft YaHei UI" when the query fails.
std::string DefaultFontFamily();

}  // namespace system_fonts

#endif  // RUNNER_SYSTEM_FONTS_H_
