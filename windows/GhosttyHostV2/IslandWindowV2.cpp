#include "IslandWindowV2.h"

#include <windows.h>
#include <windowsx.h>
#include <windows.ui.xaml.hosting.desktopwindowxamlsource.h>

#include <bit>
#include <cstdint>
#include <sstream>

#include <winrt/Windows.Foundation.Metadata.h>
#include <winrt/Windows.UI.Xaml.Hosting.h>

using namespace winrt;
using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::Foundation::Metadata;
using namespace winrt::Windows::UI::Xaml::Hosting;

bool IslandWindowV2::Create(HINSTANCE instance) noexcept
{
    _instance = instance;

    WNDCLASSW wc{};
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hInstance = instance;
    wc.lpszClassName = WindowClassName;
    wc.lpfnWndProc = WndProc;
    wc.style = CS_HREDRAW | CS_VREDRAW;
    RegisterClassW(&wc);

    _window = CreateWindowExW(
        0,
        WindowClassName,
        L"GhosttyHostV2",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        1180,
        760,
        nullptr,
        nullptr,
        instance,
        this);

    return _window != nullptr;
}

int IslandWindowV2::MessageLoop() noexcept
{
    MSG msg{};
    while (GetMessageW(&msg, nullptr, 0, 0))
    {
        if (HandleSpecialKeyMessage(msg))
        {
            continue;
        }

        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return static_cast<int>(msg.wParam);
}

LRESULT CALLBACK IslandWindowV2::WndProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) noexcept
{
    IslandWindowV2* self = nullptr;

    if (message == WM_NCCREATE)
    {
        const auto createStruct = reinterpret_cast<CREATESTRUCTW*>(lParam);
        self = reinterpret_cast<IslandWindowV2*>(createStruct->lpCreateParams);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        self->_window = hwnd;
    }
    else
    {
        self = reinterpret_cast<IslandWindowV2*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    }

    if (self)
    {
        return self->MessageHandler(message, wParam, lParam);
    }

    return DefWindowProcW(hwnd, message, wParam, lParam);
}

LRESULT IslandWindowV2::MessageHandler(UINT message, WPARAM wParam, LPARAM lParam) noexcept
{
    switch (message)
    {
    case WM_CREATE:
        if (!InitializeIsland())
        {
            return -1;
        }
        return 0;
    case WM_SIZE:
        ResizeIsland();
        return 0;
    case WM_SETFOCUS:
        if (_islandWindow)
        {
            SetFocus(_islandWindow);
        }
        _terminalSurface.FocusTerminal();
        return 0;
    case WM_MOUSEWHEEL:
    case WM_MOUSEHWHEEL:
        if (HandleMouseWheelFallback(message, wParam, lParam))
        {
            return 0;
        }
        break;
    case WM_DESTROY:
        ShutdownIsland();
        PostQuitMessage(0);
        return 0;
    case GhosttyTerminalSurfaceV2::GhosttyWakeupMessage:
        _terminalSurface.PumpRuntimeTick();
        return 0;
    }

    return DefWindowProcW(_window, message, wParam, lParam);
}

bool IslandWindowV2::InitializeIsland() noexcept
{
    std::wstring stage = L"ApiInformation checks";

    try
    {
        if (!ApiInformation::IsTypePresent(L"Windows.UI.Xaml.Hosting.DesktopWindowXamlSource"))
        {
            MessageBoxW(
                _window,
                L"DesktopWindowXamlSource is unavailable on this OS build.\nXAML Islands require Windows 10 1903+ (or newer).",
                L"GhosttyHostV2",
                MB_OK | MB_ICONERROR);
            return false;
        }

        stage = L"WindowsXamlManager::InitializeForCurrentThread";
        _xamlManager = WindowsXamlManager::InitializeForCurrentThread();

        stage = L"DesktopWindowXamlSource construction";
        _xamlSource = DesktopWindowXamlSource{};

        stage = L"AttachToWindow";
        const auto interop = _xamlSource.as<IDesktopWindowXamlSourceNative>();
        check_hresult(interop->AttachToWindow(_window));

        stage = L"Get island HWND";
        check_hresult(interop->get_WindowHandle(&_islandWindow));

        stage = L"Initialize GhosttyTerminalSurfaceV2";
        if (!_terminalSurface.Initialize(_window))
        {
            const auto& detail = _terminalSurface.LastError();
            const wchar_t* text = detail.empty()
                ? L"Failed to initialize GhosttyTerminalSurfaceV2."
                : detail.c_str();
            MessageBoxW(_window, text, L"GhosttyHostV2", MB_OK | MB_ICONERROR);
            return false;
        }

        stage = L"Set XAML content";
        _xamlSource.Content(_terminalSurface.Root());

        stage = L"ResizeIsland";
        ResizeIsland();
        _terminalSurface.FocusTerminal();
        return true;
    }
    catch (const winrt::hresult_error& ex)
    {
        std::wstringstream ss;
        ss << L"Failed to initialize host.\n\n";
        ss << L"Stage: " << stage << L"\n";
        ss << L"HRESULT: 0x" << std::hex << std::uppercase << static_cast<uint32_t>(ex.code().value) << L"\n";
        ss << L"Message: " << ex.message().c_str();
        MessageBoxW(_window, ss.str().c_str(), L"GhosttyHostV2", MB_OK | MB_ICONERROR);
        return false;
    }
    catch (...)
    {
        std::wstringstream ss;
        ss << L"Failed to initialize host.\n\n";
        ss << L"Stage: " << stage << L"\n";
        ss << L"Unknown exception";
        MessageBoxW(_window, ss.str().c_str(), L"GhosttyHostV2", MB_OK | MB_ICONERROR);
        return false;
    }
}

void IslandWindowV2::ResizeIsland() noexcept
{
    if (!_islandWindow)
    {
        return;
    }

    RECT rc{};
    GetClientRect(_window, &rc);
    const int width = (rc.right > rc.left) ? (rc.right - rc.left) : 0;
    const int height = (rc.bottom > rc.top) ? (rc.bottom - rc.top) : 0;
    SetWindowPos(
        _islandWindow,
        nullptr,
        0,
        0,
        width,
        height,
        SWP_NOACTIVATE | SWP_NOZORDER | SWP_SHOWWINDOW);

    const double scale = static_cast<double>(GetDpiForWindow(_window)) /
                         static_cast<double>(USER_DEFAULT_SCREEN_DPI);
    _terminalSurface.SetSurfaceMetrics(
        static_cast<uint32_t>(width),
        static_cast<uint32_t>(height),
        scale);
}

void IslandWindowV2::ShutdownIsland() noexcept
{
    _terminalSurface.Shutdown();

    if (_xamlSource)
    {
        _xamlSource.Close();
        _xamlSource = nullptr;
    }

    if (_xamlManager)
    {
        _xamlManager.Close();
        _xamlManager = nullptr;
    }

    _islandWindow = nullptr;
}

bool IslandWindowV2::HandleSpecialKeyMessage(const MSG& msg) noexcept
{
    if (((msg.message & ~1) == WM_KEYDOWN) || ((msg.message & ~1) == WM_SYSKEYDOWN))
    {
        const bool keyDown = (msg.message & 1) == 0;
        const auto vkey = static_cast<uint32_t>(msg.wParam);

        const bool isSpecial =
            (vkey == VK_F7 && keyDown) ||
            (vkey == VK_MENU && !keyDown) ||
            (vkey == VK_SPACE && msg.message == WM_SYSKEYDOWN);

        if (isSpecial)
        {
            const auto scanCode = static_cast<uint8_t>((msg.lParam >> 16) & 0xFF);
            if (_terminalSurface.OnDirectKeyEvent(vkey, scanCode, keyDown))
            {
                return true;
            }
        }
    }

    return false;
}

bool IslandWindowV2::HandleMouseWheelFallback(UINT message, WPARAM wParam, LPARAM lParam) noexcept
{
    if (!_window)
    {
        return false;
    }

    const int eventX = GET_X_LPARAM(lParam);
    const int eventY = GET_Y_LPARAM(lParam);

    RECT windowRect{};
    if (!GetWindowRect(_window, &windowRect))
    {
        return false;
    }

    const float dpiScale = static_cast<float>(GetDpiForWindow(_window)) / static_cast<float>(USER_DEFAULT_SCREEN_DPI);
    const float safeScale = (dpiScale <= 0.0f) ? 1.0f : dpiScale;

    const Point relative{
        static_cast<float>(eventX - windowRect.left) / safeScale,
        static_cast<float>(eventY - windowRect.top) / safeScale,
    };

    Point wheelDelta{ 0.0f, static_cast<float>(std::bit_cast<int16_t>(HIWORD(wParam))) };
    if (message == WM_MOUSEHWHEEL)
    {
        std::swap(wheelDelta.X, wheelDelta.Y);
    }

    const bool lButtonDown = (GetKeyState(VK_LBUTTON) & 0x8000) != 0;
    const bool mButtonDown = (GetKeyState(VK_MBUTTON) & 0x8000) != 0;
    const bool rButtonDown = (GetKeyState(VK_RBUTTON) & 0x8000) != 0;

    return _terminalSurface.OnMouseWheel(relative, wheelDelta, lButtonDown, mButtonDown, rButtonDown);
}
