#include "system_fonts.h"

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <set>
#include <string>
#include <vector>

#include "utils.h"

namespace system_fonts {
namespace {

constexpr wchar_t kFallbackFamily[] = L"Microsoft YaHei UI";
constexpr char kChannelName[] = "sub_converter/fonts";

// GDI reports the same family once per script/charset; the localized name
// may also differ in case. This keeps one spelling per family.
struct CaseInsensitiveLess {
  bool operator()(const std::wstring& left, const std::wstring& right) const {
    return _wcsicmp(left.c_str(), right.c_str()) < 0;
  }
};

}  // namespace

std::vector<std::string> InstalledFontFamilies() {
  std::set<std::wstring, CaseInsensitiveLess> names;
  LOGFONTW probe = {};
  probe.lfCharSet = DEFAULT_CHARSET;
  HDC dc = ::GetDC(nullptr);
  if (dc != nullptr) {
    ::EnumFontFamiliesExW(
        dc, &probe,
        [](const LOGFONTW* logfont, const TEXTMETRICW*, DWORD,
           LPARAM param) -> int {
          auto* names = reinterpret_cast<
              std::set<std::wstring, CaseInsensitiveLess>*>(param);
          if (logfont->lfFaceName[0] != L'\0' && logfont->lfFaceName[0] != L'@') {
            names->insert(std::wstring(logfont->lfFaceName));
          }
          return 1;  // continue enumeration
        },
        reinterpret_cast<LPARAM>(&names), 0);
    ::ReleaseDC(nullptr, dc);
  }
  std::vector<std::string> families;
  families.reserve(names.size());
  for (const std::wstring& name : names) {
    families.push_back(Utf8FromUtf16(name.c_str()));
  }
  return families;
}

std::string DefaultFontFamily() {
  NONCLIENTMETRICSW metrics = {};
  metrics.cbSize = sizeof(metrics);
  if (::SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, sizeof(metrics),
                              &metrics, 0) &&
      metrics.lfMessageFont.lfFaceName[0] != L'\0') {
    return Utf8FromUtf16(metrics.lfMessageFont.lfFaceName);
  }
  return Utf8FromUtf16(kFallbackFamily);
}

void RegisterChannel(flutter::BinaryMessenger* messenger) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name().compare("installedFontFamilies") == 0) {
          std::vector<flutter::EncodableValue> families;
          for (const std::string& family : InstalledFontFamilies()) {
            families.emplace_back(family);
          }
          result->Success(flutter::EncodableValue(std::move(families)));
        } else if (call.method_name().compare("defaultFontFamily") == 0) {
          result->Success(flutter::EncodableValue(DefaultFontFamily()));
        } else {
          result->NotImplemented();
        }
      });
  // The registered handler captures the channel, so the channel must outlive
  // the messenger. The window lives as long as the process anyway; keep the
  // channel alive deliberately instead of threading an owner through
  // Win32Window.
  (void)channel.release();
}

}  // namespace system_fonts
