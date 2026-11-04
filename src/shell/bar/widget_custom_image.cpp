#include "shell/bar/widget_custom_image.h"

#include "util/file_utils.h"

#include <cstdlib>
#include <filesystem>
#include <string>
#include <string_view>

namespace widget_custom_image {
  namespace {

    // A packaged desktop cannot know the user's $HOME, so the shipped config
    // points at the icon the way a user install would
    // (~/.local/share/icons/hicolor/scalable/apps/canopy-mark.svg). When that
    // file is not there - image installs, system installs, a fresh account -
    // look the same name up in the XDG data directories so the launcher shows
    // the mark instead of an empty slot.
    std::string expandAndFind(std::string_view raw) {
      const std::string expanded = FileUtils::expandUserPath(std::string(raw)).string();
      if (expanded.empty()) {
        return expanded;
      }

      std::error_code ec;
      if (std::filesystem::exists(expanded, ec)) {
        return expanded;
      }

      const auto filename = std::filesystem::path(expanded).filename();
      if (filename.empty()) {
        return expanded;
      }

      const auto searchOne = [&filename](const std::filesystem::path& root) -> std::string {
        if (root.empty()) {
          return {};
        }
        std::error_code inner;
        const auto candidate = root / "icons" / "hicolor" / "scalable" / "apps" / filename;
        if (std::filesystem::exists(candidate, inner)) {
          return candidate.string();
        }
        return {};
      };

      const auto* dataHome = std::getenv("XDG_DATA_HOME");
      const auto* home = std::getenv("HOME");
      if (dataHome != nullptr && dataHome[0] != '\0') {
        if (auto hit = searchOne(dataHome); !hit.empty()) {
          return hit;
        }
      } else if (home != nullptr && home[0] != '\0') {
        if (auto hit = searchOne(std::filesystem::path(home) / ".local" / "share"); !hit.empty()) {
          return hit;
        }
      }

      const char* dataDirs = std::getenv("XDG_DATA_DIRS");
      const std::string_view dirs = (dataDirs != nullptr && dataDirs[0] != '\0')
                                        ? std::string_view{dataDirs}
                                        : std::string_view{"/usr/local/share:/usr/share"};
      std::size_t begin = 0;
      while (begin <= dirs.size()) {
        const auto end = dirs.find(':', begin);
        const auto entry =
            dirs.substr(begin, end == std::string_view::npos ? std::string_view::npos : end - begin);
        if (!entry.empty()) {
          if (auto hit = searchOne(entry); !hit.empty()) {
            return hit;
          }
        }
        if (end == std::string_view::npos) {
          break;
        }
        begin = end + 1;
      }

      return expanded;
    }

  } // namespace

  WidgetCustomImage fromConfig(const std::string& path, bool colorize) {
    return {
        .path = expandAndFind(path),
        .colorize = colorize,
    };
  }

} // namespace widget_custom_image
