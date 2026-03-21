#include "IslandWindowV2.h"
#include "GhosttyApiShim.h"

#include <windows.h>

#include <winrt/base.h>

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int)
{
    winrt::init_apartment(winrt::apartment_type::single_threaded);
    EnableMouseInPointer(TRUE);

    const int initResult = ghostty_init(static_cast<uintptr_t>(__argc), __argv);
    if (initResult != GHOSTTY_SUCCESS)
    {
        MessageBoxW(nullptr, L"ghostty_init failed.", L"GhosttyHostV2", MB_OK | MB_ICONERROR);
        return initResult;
    }

    IslandWindowV2 window;
    if (!window.Create(instance))
    {
        return static_cast<int>(GetLastError());
    }

    return window.MessageLoop();
}
