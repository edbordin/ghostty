#include "IslandWindow.h"

#include <windows.h>

#include <winrt/base.h>

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int)
{
    winrt::init_apartment(winrt::apartment_type::single_threaded);

    IslandWindow window;
    if (!window.Create(instance))
    {
        return static_cast<int>(GetLastError());
    }

    return window.MessageLoop();
}
