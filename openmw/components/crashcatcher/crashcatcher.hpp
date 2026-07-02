#ifndef OPENMW_COMPONENTS_CRASHCATCHER_CRASHCATCHER_HPP
#define OPENMW_COMPONENTS_CRASHCATCHER_CRASHCATCHER_HPP

#include <filesystem>

#if (defined(__APPLE__) || (defined(__linux) && !defined(ANDROID)) || (defined(__unix) && !defined(ANDROID))           \
    || defined(__posix)) && !defined(__EMSCRIPTEN__)
void crashCatcherInstall(int argc, char** argv, const std::filesystem::path& crashLogPath);
#else
inline void crashCatcherInstall(int /*argc*/, char** /*argv*/, const std::filesystem::path& /*crashLogPath*/) {}
#endif

#endif
