#include "IslandWindowV2.h"
#include "GhosttyApiShim.h"

#include <windows.h>

#include <iterator>
#include <winrt/base.h>

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int)
{
    winrt::init_apartment(winrt::apartment_type::single_threaded);
    EnableMouseInPointer(TRUE);

    wchar_t skipInitBuf[8]{};
    const auto skipInitLen = GetEnvironmentVariableW(
        L"GHOSTTY_SKIP_INIT",
        skipInitBuf,
        static_cast<DWORD>(std::size(skipInitBuf)));
    const bool skipInit = skipInitLen > 0 && skipInitBuf[0] == L'1';

    if (!skipInit)
    {
        wchar_t initNoArgsBuf[8]{};
        const auto initNoArgsLen = GetEnvironmentVariableW(
            L"GHOSTTY_INIT_NO_ARGS",
            initNoArgsBuf,
            static_cast<DWORD>(std::size(initNoArgsBuf)));
        const bool initNoArgs = initNoArgsLen > 0 && initNoArgsBuf[0] == L'1';

        const uintptr_t argcForInit = initNoArgs ? 0u : static_cast<uintptr_t>(__argc);
        const int initResult = ghostty_init(argcForInit, __argv);
        if (initResult != GHOSTTY_SUCCESS)
        {
            MessageBoxW(nullptr, L"ghostty_init failed.", L"GhosttyHostV2", MB_OK | MB_ICONERROR);
            return initResult;
        }
    }

    wchar_t skipWindowBuf[8]{};
    const auto skipWindowLen = GetEnvironmentVariableW(
        L"GHOSTTY_SKIP_WINDOW_CREATE",
        skipWindowBuf,
        static_cast<DWORD>(std::size(skipWindowBuf)));
    const bool skipWindowCreate = skipWindowLen > 0 && skipWindowBuf[0] == L'1';
    if (skipWindowCreate)
    {
        return 0;
    }

    IslandWindowV2 window;
    if (!window.Create(instance))
    {
        return static_cast<int>(GetLastError());
    }

    return window.MessageLoop();
}
