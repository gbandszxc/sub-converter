#include "system_fonts.h"

#include <windows.h>

#include <dwrite.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <set>
#include <string>
#include <vector>

#include "utils.h"

namespace system_fonts {
namespace {

constexpr wchar_t kFallbackFamily[] = L"Microsoft YaHei UI";
constexpr char kChannelName[] = "sub_converter/fonts";

// The localized name may be reported by several locales or differ in case.
// This keeps one spelling per family.
struct CaseInsensitiveLess {
  bool operator()(const std::wstring& left, const std::wstring& right) const {
    return _wcsicmp(left.c_str(), right.c_str()) < 0;
  }
};

// DirectWrite resolves text by typographic family, so weight-split GDI
// families ("Microsoft YaHei UI Light", "MiSans Demibold", "等线 Light") are
// not families the engine can match by name - they are faces of their base
// family. Enumerating the DirectWrite system collection therefore yields
// exactly the names Flutter can render.
std::wstring FirstLocalizedFaceName(IDWriteLocalizedStrings* names) {
  wchar_t locale[LOCALE_NAME_MAX_LENGTH] = {};
  if (::GetUserDefaultLocaleName(locale, LOCALE_NAME_MAX_LENGTH) == 0) {
    wcscpy_s(locale, L"en-us");
  }
  UINT32 index = 0;
  BOOL exists = FALSE;
  if (FAILED(names->FindLocaleName(locale, &index, &exists)) || !exists) {
    if (FAILED(names->FindLocaleName(L"en-us", &index, &exists)) || !exists) {
      index = 0;
    }
  }
  UINT32 length = 0;
  if (FAILED(names->GetStringLength(index, &length))) {
    return std::wstring();
  }
  std::wstring name(length, L'\0');
  if (FAILED(names->GetString(index, &name[0], length + 1))) {
    name.clear();
  }
  return name;
}

}  // namespace

std::vector<std::string> InstalledFontFamilies() {
  std::vector<std::string> families;
  IDWriteFactory* factory = nullptr;
  if (FAILED(::DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED,
                                   __uuidof(IDWriteFactory),
                                   reinterpret_cast<IUnknown**>(&factory))) ||
      factory == nullptr) {
    return families;
  }
  IDWriteFontCollection* collection = nullptr;
  if (SUCCEEDED(factory->GetSystemFontCollection(&collection, FALSE)) &&
      collection != nullptr) {
    std::set<std::wstring, CaseInsensitiveLess> names;
    const UINT32 count = collection->GetFontFamilyCount();
    for (UINT32 i = 0; i < count; ++i) {
      IDWriteFontFamily* family = nullptr;
      if (FAILED(collection->GetFontFamily(i, &family)) || family == nullptr) {
        continue;
      }
      IDWriteLocalizedStrings* family_names = nullptr;
      if (SUCCEEDED(family->GetFamilyNames(&family_names)) &&
          family_names != nullptr) {
        const std::wstring name = FirstLocalizedFaceName(family_names);
        if (!name.empty() && name[0] != L'@') {
          names.insert(name);
        }
        family_names->Release();
      }
      family->Release();
    }
    for (const std::wstring& name : names) {
      families.push_back(Utf8FromUtf16(name.c_str()));
    }
    collection->Release();
  }
  factory->Release();
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
