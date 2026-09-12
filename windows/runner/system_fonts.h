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

// Every installed font family name as GDI spells it, sorted
// case-insensitively. Vertical variants (leading '@') and duplicates are
// removed.
std::vector<std::string> InstalledFontFamilies();

// The family the shell uses for its own UI text (NONCLIENTMETRICS
// lfMessageFont): "Microsoft YaHei UI" on Chinese Windows, "Segoe UI" on
// English Windows, "Meiryo UI" on Japanese Windows, and so on. Falls back to
// "Microsoft YaHei UI" when the query fails.
std::string DefaultFontFamily();

}  // namespace system_fonts

#endif  // RUNNER_SYSTEM_FONTS_H_
