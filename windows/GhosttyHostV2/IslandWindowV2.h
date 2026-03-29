#pragma once

#include <windows.h>

#ifdef GetCurrentTime
#undef GetCurrentTime
#endif

#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.UI.Xaml.Hosting.h>

#include "GhosttyTerminalSurfaceV2.h"

class IslandWindowV2
{
public:
    bool Create(HINSTANCE instance) noexcept;
    int MessageLoop() noexcept;

private:
    static constexpr wchar_t WindowClassName[] = L"GhosttyIslandHostWindowV2";

    static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) noexcept;
    LRESULT MessageHandler(UINT message, WPARAM wParam, LPARAM lParam) noexcept;

    bool InitializeIsland() noexcept;
    void ResizeIsland() noexcept;
    void ShutdownIsland() noexcept;
    bool HandleSpecialKeyMessage(const MSG& msg) noexcept;
    bool HandleMouseWheelFallback(UINT message, WPARAM wParam, LPARAM lParam) noexcept;

    HWND _window{ nullptr };
    HWND _islandWindow{ nullptr };
    HINSTANCE _instance{ nullptr };
    winrt::Windows::UI::Xaml::Hosting::WindowsXamlManager _xamlManager{ nullptr };
    winrt::Windows::UI::Xaml::Hosting::DesktopWindowXamlSource _xamlSource{ nullptr };
    GhosttyTerminalSurfaceV2 _terminalSurface{};
};
