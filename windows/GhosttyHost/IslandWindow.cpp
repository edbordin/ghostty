#include "IslandWindow.h"

#include "WinUiContent.h"

#include <windows.h>
#include <windows.ui.xaml.hosting.desktopwindowxamlsource.h>

#if defined(_WIN32)
#include <BaseTsd.h>
typedef SSIZE_T ssize_t;
#endif

#include <ghostty.h>

#include <cstdint>
#include <string>
#include <sstream>

#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Metadata.h>
#include <winrt/Windows.UI.Xaml.h>

using namespace winrt;
using namespace winrt::Windows::Foundation::Metadata;
using namespace winrt::Windows::UI::Xaml;
using namespace winrt::Windows::UI::Xaml::Hosting;

bool IslandWindow::Create(HINSTANCE instance) noexcept
{
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
        L"Ghostty Windows Host",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        1024,
        700,
        nullptr,
        nullptr,
        instance,
        this);

    return _window != nullptr;
}

int IslandWindow::MessageLoop() const noexcept
{
    MSG msg{};
    while (GetMessageW(&msg, nullptr, 0, 0))
    {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return static_cast<int>(msg.wParam);
}

LRESULT CALLBACK IslandWindow::WndProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) noexcept
{
    IslandWindow* self = nullptr;

    if (message == WM_NCCREATE)
    {
        const auto createStruct = reinterpret_cast<CREATESTRUCTW*>(lParam);
        self = reinterpret_cast<IslandWindow*>(createStruct->lpCreateParams);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        self->_window = hwnd;
    }
    else
    {
        self = reinterpret_cast<IslandWindow*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    }

    if (self)
    {
        return self->MessageHandler(message, wParam, lParam);
    }

    return DefWindowProcW(hwnd, message, wParam, lParam);
}

LRESULT IslandWindow::MessageHandler(UINT message, WPARAM wParam, LPARAM lParam) noexcept
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
            return 0;
        }
        break;
    case WM_DESTROY:
        ShutdownIsland();
        PostQuitMessage(0);
        return 0;
    }

    return DefWindowProcW(_window, message, wParam, lParam);
}

bool IslandWindow::InitializeIsland() noexcept
{
    std::wstring stage = L"ApiInformation checks";

    try
    {
        if (!ApiInformation::IsTypePresent(L"Windows.UI.Xaml.Hosting.DesktopWindowXamlSource"))
        {
            MessageBoxW(
                _window,
                L"DesktopWindowXamlSource is unavailable on this OS build.\nXAML Islands require Windows 10 1903+ (or newer).",
                L"GhosttyHost",
                MB_OK | MB_ICONERROR);
            return false;
        }

        stage = L"WindowsXamlManager::InitializeForCurrentThread";
        _xamlManager = WindowsXamlManager::InitializeForCurrentThread();

        stage = L"DesktopWindowXamlSource construction";
        _xamlSource = DesktopWindowXamlSource{};

        stage = L"IDesktopWindowXamlSourceNative::AttachToWindow";
        const auto interop = _xamlSource.as<IDesktopWindowXamlSourceNative>();
        check_hresult(interop->AttachToWindow(_window));

        stage = L"IDesktopWindowXamlSourceNative::get_WindowHandle";
        check_hresult(interop->get_WindowHandle(&_islandWindow));

        stage = L"ghostty_info";
        std::string versionUtf8;
        const ghostty_info_s info = ghostty_info();
        versionUtf8.assign(info.version, info.version_len);
        const hstring version = !versionUtf8.empty() ? to_hstring(versionUtf8) : hstring{ L"(unavailable)" };

        stage = L"CreateGhosttyRootContent / Content assignment";
        _xamlSource.Content(CreateGhosttyRootContent(version));

        stage = L"ResizeIsland";
        ResizeIsland();
        return true;
    }
    catch (const winrt::hresult_error& ex)
    {
        std::wstringstream ss;
        ss << L"Failed to initialize XAML island host.\n\n";
        ss << L"Stage: " << stage << L"\n";
        ss << L"HRESULT: 0x" << std::hex << std::uppercase << static_cast<uint32_t>(ex.code().value) << L"\n";
        ss << L"Message: " << ex.message().c_str();

        MessageBoxW(_window, ss.str().c_str(), L"GhosttyHost", MB_OK | MB_ICONERROR);
        return false;
    }
    catch (const std::exception& ex)
    {
        std::wstringstream ss;
        ss << L"Failed to initialize XAML island host.\n\n";
        ss << L"Stage: " << stage << L"\n";
        ss << L"std::exception: " << ex.what();

        MessageBoxW(_window, ss.str().c_str(), L"GhosttyHost", MB_OK | MB_ICONERROR);
        return false;
    }
    catch (...)
    {
        std::wstringstream ss;
        ss << L"Failed to initialize XAML island host.\n\n";
        ss << L"Stage: " << stage << L"\n";
        ss << L"Unknown exception";

        MessageBoxW(_window, ss.str().c_str(), L"GhosttyHost", MB_OK | MB_ICONERROR);
        return false;
    }
}

void IslandWindow::ResizeIsland() noexcept
{
    if (!_islandWindow)
    {
        return;
    }

    RECT rc{};
    GetClientRect(_window, &rc);
    SetWindowPos(
        _islandWindow,
        nullptr,
        0,
        0,
        rc.right - rc.left,
        rc.bottom - rc.top,
        SWP_NOACTIVATE | SWP_NOZORDER | SWP_SHOWWINDOW);
}

void IslandWindow::ShutdownIsland() noexcept
{
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
