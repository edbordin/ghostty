#pragma once

#include <windows.h>

#ifdef GetCurrentTime
#undef GetCurrentTime
#endif

#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.UI.Xaml.Controls.h>
#include <winrt/Windows.UI.Xaml.Hosting.h>

class IslandWindow
{
public:
    bool Create(HINSTANCE instance) noexcept;
    int MessageLoop() const noexcept;

private:
    static constexpr wchar_t WindowClassName[] = L"GhosttyIslandHostWindow";

    static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) noexcept;
    LRESULT MessageHandler(UINT message, WPARAM wParam, LPARAM lParam) noexcept;

    bool InitializeIsland() noexcept;
    void ResizeIsland() noexcept;
    void ShutdownIsland() noexcept;

    HWND _window{ nullptr };
    HWND _islandWindow{ nullptr };
    winrt::Windows::UI::Xaml::Hosting::WindowsXamlManager _xamlManager{ nullptr };
    winrt::Windows::UI::Xaml::Hosting::DesktopWindowXamlSource _xamlSource{ nullptr };
};
