#include "GhosttyTerminalSurfaceV2.h"

#include <windows.ui.xaml.media.dxinterop.h>

#include <cmath>
#include <cstdint>
#include <iterator>
#include <iostream>
#include <sstream>
#include <string>

#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.h>
#include <winrt/Windows.UI.Input.h>
#include <winrt/Windows.UI.Xaml.Media.h>

using namespace winrt;
using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::System;
using namespace winrt::Windows::UI::Input;
using namespace winrt::Windows::UI::Xaml;
using namespace winrt::Windows::UI::Xaml::Controls;
using namespace winrt::Windows::UI::Xaml::Input;
using namespace winrt::Windows::UI::Xaml::Media;

namespace
{
    static ghostty_surface_t TryCreateGhosttySurface(
        ghostty_app_t app,
        const ghostty_surface_config_s* config,
        DWORD* exceptionCode) noexcept
    {
        if (exceptionCode)
        {
            *exceptionCode = 0;
        }

#if defined(_MSC_VER)
        __try
        {
            return ghostty_surface_new(app, config);
        }
        __except (EXCEPTION_EXECUTE_HANDLER)
        {
            if (exceptionCode)
            {
                *exceptionCode = GetExceptionCode();
            }
            return nullptr;
        }
#else
        (void)exceptionCode;
        return ghostty_surface_new(app, config);
#endif
    }

    static std::string Utf8FromCodepoint(uint32_t cp)
    {
        std::string result;
        if (cp <= 0x7F)
        {
            result.push_back(static_cast<char>(cp));
            return result;
        }

        if (cp <= 0x7FF)
        {
            result.push_back(static_cast<char>(0xC0u | ((cp >> 6) & 0x1Fu)));
            result.push_back(static_cast<char>(0x80u | (cp & 0x3Fu)));
            return result;
        }

        if (cp <= 0xFFFF)
        {
            result.push_back(static_cast<char>(0xE0u | ((cp >> 12) & 0x0Fu)));
            result.push_back(static_cast<char>(0x80u | ((cp >> 6) & 0x3Fu)));
            result.push_back(static_cast<char>(0x80u | (cp & 0x3Fu)));
            return result;
        }

        if (cp <= 0x10FFFF)
        {
            result.push_back(static_cast<char>(0xF0u | ((cp >> 18) & 0x07u)));
            result.push_back(static_cast<char>(0x80u | ((cp >> 12) & 0x3Fu)));
            result.push_back(static_cast<char>(0x80u | ((cp >> 6) & 0x3Fu)));
            result.push_back(static_cast<char>(0x80u | (cp & 0x3Fu)));
            return result;
        }

        return {};
    }

    static std::wstring DescribeKeyEvent(const KeyRoutedEventArgs& e, bool keyDown)
    {
        std::wstringstream ss;
        const auto keyStatus = e.KeyStatus();
        ss << (keyDown ? L"KeyDown " : L"KeyUp ")
           << static_cast<uint32_t>(e.OriginalKey())
           << L" scan=" << keyStatus.ScanCode;
        return ss.str();
    }

    static bool HostTraceEnabled() noexcept
    {
        static int cached = -1;
        if (cached >= 0)
        {
            return cached == 1;
        }

        wchar_t buf[16]{};
        const auto len = GetEnvironmentVariableW(
            L"GHOSTTY_TRACE_HOST",
            buf,
            static_cast<DWORD>(std::size(buf)));

        if (len == 0)
        {
            cached = 1;
            return true;
        }

        const wchar_t ch = buf[0];
        cached = (ch == L'0' || ch == L'f' || ch == L'F' || ch == L'n' || ch == L'N') ? 0 : 1;
        return cached == 1;
    }

    static bool HostOverlayEnabled() noexcept
    {
        static int cached = -1;
        if (cached >= 0)
        {
            return cached == 1;
        }

        wchar_t buf[16]{};
        const auto len = GetEnvironmentVariableW(
            L"GHOSTTY_HOST_OVERLAY",
            buf,
            static_cast<DWORD>(std::size(buf)));

        if (len == 0)
        {
            cached = 0;
            return false;
        }

        const wchar_t ch = buf[0];
        cached = (ch == L'0' || ch == L'f' || ch == L'F' || ch == L'n' || ch == L'N') ? 0 : 1;
        return cached == 1;
    }
}

bool GhosttyTerminalSurfaceV2::Initialize(HWND ownerWindow) noexcept
{
    _ownerWindow = ownerWindow;
    _lastError.clear();
    _runtimeInitialized = false;
    _runtimeInitDeferred = false;
    _swapChainSizeChangedRegistered = false;
    _swapChainScaleChangedRegistered = false;
    std::wstring stage = L"Create root controls";

    try
    {
        _root = UserControl{};
        _layout = Grid{};
        _versionText = TextBlock{};
        _statusText = TextBlock{};

        _root.IsTabStop(true);

        bool swapChainReady = false;
        stage = L"Create SwapChainPanel";
        try
        {
            _swapChainPanel = SwapChainPanel{};
            _swapChainPanel.HorizontalAlignment(HorizontalAlignment::Stretch);
            _swapChainPanel.VerticalAlignment(VerticalAlignment::Stretch);
            _layout.Children().Append(_swapChainPanel);
            swapChainReady = true;
        }
        catch (const hresult_error& ex)
        {
            std::wstringstream ss;
            ss << L"SwapChainPanel unavailable (0x"
               << std::hex << std::uppercase << static_cast<uint32_t>(ex.code().value)
               << L"): " << ex.message().c_str();
            _lastError = ss.str();
            if (HostTraceEnabled())
            {
                std::cerr << "[host] swapchain panel setup failed hr=0x"
                          << std::hex << std::uppercase << static_cast<uint32_t>(ex.code().value)
                          << std::dec << std::nouppercase
                          << " message=" << winrt::to_string(ex.message())
                          << std::endl;
            }

            auto fallback = Border{};
            fallback.HorizontalAlignment(HorizontalAlignment::Stretch);
            fallback.VerticalAlignment(VerticalAlignment::Stretch);
            fallback.Background(SolidColorBrush{ winrt::Windows::UI::ColorHelper::FromArgb(255, 22, 22, 24) });
            _layout.Children().Append(fallback);
        }

        _versionText.Text(L"libghostty: (loading)");
        _statusText.Text(L"Status: Initializing");
        _statusText.TextWrapping(TextWrapping::Wrap);

        if (HostOverlayEnabled())
        {
            stage = L"Create overlay";
            auto overlay = StackPanel{};
            overlay.Margin(ThicknessHelper::FromUniformLength(12.0));
            overlay.Orientation(Orientation::Vertical);
            overlay.HorizontalAlignment(HorizontalAlignment::Left);
            overlay.VerticalAlignment(VerticalAlignment::Top);

            auto titleText = TextBlock{};
            titleText.Text(L"GhosttyHostV2");
            titleText.FontSize(22.0);

            auto subtitleText = TextBlock{};
            subtitleText.Text(L"Terminal-style input and swapchain surface scaffold");
            subtitleText.Opacity(0.82);

            overlay.Children().Append(titleText);
            overlay.Children().Append(subtitleText);
            overlay.Children().Append(_versionText);
            overlay.Children().Append(_statusText);

            stage = L"Attach overlay";
            _layout.Children().Append(overlay);
        }

        stage = L"Attach layout to root";
        _root.Content(_layout);

        stage = L"Update version";
        _UpdateVersion();

        stage = L"Wire input handlers";
        _WireInputHandlers();

        stage = L"Initialize Ghostty runtime";
        const bool skipRuntimeInit = []() noexcept {
            wchar_t buf[8]{};
            const auto len = GetEnvironmentVariableW(
                L"GHOSTTY_SKIP_RUNTIME_INIT",
                buf,
                static_cast<DWORD>(std::size(buf)));
            return len > 0 && buf[0] == L'1';
        }();

        if (skipRuntimeInit)
        {
            _SetStatus(L"Status: Runtime init skipped (GHOSTTY_SKIP_RUNTIME_INIT=1)");
        }
        else if (swapChainReady)
        {
            stage = L"Wait for SwapChainPanel layout";
            _runtimeInitDeferred = true;
            _SetStatus(L"Status: Waiting for SwapChainPanel layout");

            _swapChainSizeChangedToken = _swapChainPanel.SizeChanged(
                [this](const IInspectable&, const SizeChangedEventArgs&) {
                    _ApplyPanelMetrics();
                    _TryInitializeGhosttyRuntimeOnLayout();
                });
            _swapChainSizeChangedRegistered = true;

            _swapChainScaleChangedToken = _swapChainPanel.CompositionScaleChanged(
                [this](const SwapChainPanel&, const IInspectable&) {
                    _ApplyPanelMetrics();
                    _TryInitializeGhosttyRuntimeOnLayout();
                });
            _swapChainScaleChangedRegistered = true;

            auto revoker = _swapChainPanel.LayoutUpdated(
                winrt::auto_revoke,
                [this](const IInspectable&, const IInspectable&) {
                    _TryInitializeGhosttyRuntimeOnLayout();
                });
            _swapChainLayoutUpdatedRevoker.swap(revoker);

            // Attempt immediate init in case layout already happened.
            _TryInitializeGhosttyRuntimeOnLayout();
        }
        else if (!_InitializeGhosttyRuntime())
        {
            _SetStatus(L"Status: Runtime init failed (see logs)");
        }
        else
        {
            _runtimeInitialized = true;
            _SetStatus(L"Status: Runtime + surface ready (fallback surface active)");
        }

        return true;
    }
    catch (const hresult_error& ex)
    {
        std::wstringstream ss;
        ss << L"GhosttyTerminalSurfaceV2 init failed.\n";
        ss << L"Stage: " << stage << L"\n";
        ss << L"HRESULT: 0x" << std::hex << std::uppercase << static_cast<uint32_t>(ex.code().value) << L"\n";
        ss << L"Message: " << ex.message().c_str();
        _lastError = ss.str();
        return false;
    }
    catch (const std::exception& ex)
    {
        std::wstringstream ss;
        ss << L"GhosttyTerminalSurfaceV2 init failed.\n";
        ss << L"Stage: " << stage << L"\n";
        ss << L"std::exception: " << to_hstring(ex.what()).c_str();
        _lastError = ss.str();
        return false;
    }
    catch (...)
    {
        std::wstringstream ss;
        ss << L"GhosttyTerminalSurfaceV2 init failed.\n";
        ss << L"Stage: " << stage << L"\n";
        ss << L"Unknown exception";
        _lastError = ss.str();
        return false;
    }
}

void GhosttyTerminalSurfaceV2::Shutdown() noexcept
{
    if (_swapChainPanel && _swapChainSizeChangedRegistered)
    {
        _swapChainPanel.SizeChanged(_swapChainSizeChangedToken);
    }
    if (_swapChainPanel && _swapChainScaleChangedRegistered)
    {
        _swapChainPanel.CompositionScaleChanged(_swapChainScaleChangedToken);
    }
    _swapChainSizeChangedRegistered = false;
    _swapChainScaleChangedRegistered = false;
    _swapChainLayoutUpdatedRevoker.revoke();
    _ShutdownGhosttyRuntime();
}

bool GhosttyTerminalSurfaceV2::PumpRuntimeTick() noexcept
{
    if (!_ghosttyApp)
    {
        return false;
    }

    _runtimeTickScheduled.store(false);
    ghostty_app_tick(_ghosttyApp);
    if (_ghosttySurface)
    {
        ghostty_surface_draw(_ghosttySurface);
    }
    return true;
}

const std::wstring& GhosttyTerminalSurfaceV2::LastError() const noexcept
{
    return _lastError;
}

UIElement GhosttyTerminalSurfaceV2::Root() const noexcept
{
    return _root;
}

void GhosttyTerminalSurfaceV2::FocusTerminal() noexcept
{
    if (_root)
    {
        _root.Focus(FocusState::Programmatic);
    }
}

void GhosttyTerminalSurfaceV2::SetSurfaceMetrics(uint32_t widthPx, uint32_t heightPx, double scaleX, double scaleY) noexcept
{
    if (!_ghosttySurface)
    {
        return;
    }

    ghostty_surface_set_content_scale(_ghosttySurface, scaleX, scaleY);
    ghostty_surface_set_size(_ghosttySurface, widthPx, heightPx);
}

bool GhosttyTerminalSurfaceV2::OnDirectKeyEvent(uint32_t vkey, uint8_t scanCode, bool down) noexcept
{
    const bool isAltPressed = (GetKeyState(VK_MENU) & 0x8000) != 0;

    if ((vkey == VK_F7 && down) ||
        (vkey == VK_MENU && !down) ||
        (vkey == VK_SPACE && down && isAltPressed))
    {
        const bool handled = _SendKeyToGhostty(scanCode, down);

        std::wstringstream ss;
        ss << L"Status: DirectKey vkey=" << vkey
           << L" scan=" << static_cast<uint32_t>(scanCode)
           << L" down=" << (down ? L"true" : L"false")
           << L" ghostty=" << (handled ? L"handled" : L"pass");
        _SetStatus(ss.str());
        return handled;
    }

    return false;
}

bool GhosttyTerminalSurfaceV2::OnMouseWheel(const Point& location,
                                            const Point& delta,
                                            bool leftButtonDown,
                                            bool middleButtonDown,
                                            bool rightButtonDown) noexcept
{
    std::wstringstream ss;
    ss << L"Status: Win32 wheel fallback x=" << location.X
       << L" y=" << location.Y
       << L" dx=" << delta.X
       << L" dy=" << delta.Y
       << L" buttons=("
       << (leftButtonDown ? L"L" : L"-")
       << (middleButtonDown ? L"M" : L"-")
       << (rightButtonDown ? L"R" : L"-")
       << L")";
    _SetStatus(ss.str());
    return true;
}

void GhosttyTerminalSurfaceV2::AttachSwapChainHandle(HANDLE swapChainHandle) noexcept
{
    if (!_swapChainPanel)
    {
        return;
    }

    try
    {
        auto nativePanel = _swapChainPanel.as<ISwapChainPanelNative2>();
        check_hresult(nativePanel->SetSwapChainHandle(swapChainHandle));
        _SetStatus(L"Status: SwapChain handle attached");
    }
    catch (const hresult_error& ex)
    {
        std::wstringstream ss;
        ss << L"Status: SwapChain attach failed (0x"
           << std::hex << std::uppercase << static_cast<uint32_t>(ex.code().value)
           << L")";
        _SetStatus(ss.str());
    }
}

void GhosttyTerminalSurfaceV2::_TryInitializeGhosttyRuntimeOnLayout() noexcept
{
    if (_runtimeInitialized || !_runtimeInitDeferred || !_swapChainPanel)
    {
        return;
    }

    const double widthDip = _swapChainPanel.ActualWidth();
    const double heightDip = _swapChainPanel.ActualHeight();
    const double scaleX = _swapChainPanel.CompositionScaleX();
    const double scaleY = _swapChainPanel.CompositionScaleY();

    if (widthDip <= 0.0 || heightDip <= 0.0 || scaleX <= 0.0 || scaleY <= 0.0)
    {
        return;
    }

    const uint32_t widthPx = static_cast<uint32_t>(std::llround(widthDip * scaleX));
    const uint32_t heightPx = static_cast<uint32_t>(std::llround(heightDip * scaleY));
    if (HostTraceEnabled())
    {
        std::cerr << "[host] panel layout ready actual=" << widthDip << "x" << heightDip
                  << " scale=" << scaleX << "x" << scaleY
                  << " pixels=" << widthPx << "x" << heightPx
                  << std::endl;
    }

    if (!_InitializeGhosttyRuntime())
    {
        _runtimeInitDeferred = false;
        _swapChainLayoutUpdatedRevoker.revoke();
        _SetStatus(L"Status: Runtime init failed (see logs)");
        return;
    }

    _runtimeInitialized = true;
    _runtimeInitDeferred = false;
    _swapChainLayoutUpdatedRevoker.revoke();
    _ApplyPanelMetrics();
    _SetStatus(L"Status: Runtime + surface ready");
}

void GhosttyTerminalSurfaceV2::_ApplyPanelMetrics() noexcept
{
    if (!_swapChainPanel)
    {
        return;
    }

    const double widthDip = _swapChainPanel.ActualWidth();
    const double heightDip = _swapChainPanel.ActualHeight();
    const double scaleX = _swapChainPanel.CompositionScaleX();
    const double scaleY = _swapChainPanel.CompositionScaleY();
    if (widthDip <= 0.0 || heightDip <= 0.0 || scaleX <= 0.0 || scaleY <= 0.0)
    {
        return;
    }

    const auto widthPx = static_cast<uint32_t>(std::llround(widthDip * scaleX));
    const auto heightPx = static_cast<uint32_t>(std::llround(heightDip * scaleY));
    SetSurfaceMetrics(widthPx, heightPx, scaleX, scaleY);
}

bool GhosttyTerminalSurfaceV2::_InitializeGhosttyRuntime() noexcept
{
    _ShutdownGhosttyRuntime();

    const wchar_t* stage = L"ghostty_config_new";
    if (HostTraceEnabled()) std::cerr << "[host] runtime_init begin" << std::endl;

    try
    {
        _ghosttyConfig = ghostty_config_new();
        if (!_ghosttyConfig)
        {
            if (HostTraceEnabled()) std::cerr << "[host] runtime_init failed at ghostty_config_new (null config)" << std::endl;
            _lastError = L"Ghostty runtime init failed.\nStage: ghostty_config_new\nResult: null config";
            return false;
        }

        const bool loadDefaultConfig = []() noexcept {
            wchar_t buf[8]{};
            const auto len = GetEnvironmentVariableW(
                L"GHOSTTY_LOAD_DEFAULT_CONFIG",
                buf,
                static_cast<DWORD>(std::size(buf)));
            return len > 0 && buf[0] == L'1';
        }();
        if (loadDefaultConfig)
        {
            stage = L"ghostty_config_load_default_files";
            ghostty_config_load_default_files(_ghosttyConfig);
            if (HostTraceEnabled()) std::cerr << "[host] runtime_init loaded default config files" << std::endl;
        }
        else
        {
            if (HostTraceEnabled())
            {
                std::cerr << "[host] runtime_init skipping default config file load "
                             "(set GHOSTTY_LOAD_DEFAULT_CONFIG=1 to enable)"
                          << std::endl;
            }
        }

        stage = L"ghostty_config_finalize";
        ghostty_config_finalize(_ghosttyConfig);

        stage = L"ghostty_app_new";
        ghostty_runtime_config_s runtimeConfig{};
        runtimeConfig.userdata = this;
        runtimeConfig.supports_selection_clipboard = false;
        runtimeConfig.wakeup_cb = &GhosttyTerminalSurfaceV2::_RuntimeWakeupCallback;
        runtimeConfig.action_cb = &GhosttyTerminalSurfaceV2::_RuntimeActionCallback;
        runtimeConfig.read_clipboard_cb = &GhosttyTerminalSurfaceV2::_RuntimeReadClipboardCallback;
        runtimeConfig.confirm_read_clipboard_cb = &GhosttyTerminalSurfaceV2::_RuntimeConfirmReadClipboardCallback;
        runtimeConfig.write_clipboard_cb = &GhosttyTerminalSurfaceV2::_RuntimeWriteClipboardCallback;
        runtimeConfig.close_surface_cb = &GhosttyTerminalSurfaceV2::_RuntimeCloseSurfaceCallback;

        _ghosttyApp = ghostty_app_new(&runtimeConfig, _ghosttyConfig);
        if (!_ghosttyApp)
        {
            if (HostTraceEnabled()) std::cerr << "[host] runtime_init failed at ghostty_app_new (null app)" << std::endl;
            _lastError = L"Ghostty runtime init failed.\nStage: ghostty_app_new\nResult: null app";
            _ShutdownGhosttyRuntime();
            return false;
        }
        if (HostTraceEnabled()) std::cerr << "[host] runtime_init app created ptr=" << _ghosttyApp << std::endl;

        const bool enableSurface = []() noexcept {
            wchar_t buf[8]{};
            const auto len = GetEnvironmentVariableW(L"GHOSTTY_ENABLE_SURFACE", buf, static_cast<DWORD>(std::size(buf)));
            if (len == 0)
            {
                return true;
            }

            const wchar_t ch = buf[0];
            return !(ch == L'0' || ch == L'f' || ch == L'F' || ch == L'n' || ch == L'N');
        }();

        if (!enableSurface)
        {
            if (HostTraceEnabled()) std::cerr << "[host] runtime_init surface disabled by env" << std::endl;
            _SetStatus(L"Status: Runtime ready (surface disabled; set GHOSTTY_ENABLE_SURFACE=1 to test)");
            return true;
        }

        stage = L"ghostty_surface_new";
        auto surfaceConfig = ghostty_surface_config_new();
        surfaceConfig.platform_tag = GHOSTTY_PLATFORM_WINDOWS;
        surfaceConfig.platform.windows.hwnd = _ownerWindow;
        surfaceConfig.platform.windows.swap_chain_panel = nullptr;
        if (_swapChainPanel)
        {
            try
            {
                auto nativePanel = _swapChainPanel.as<ISwapChainPanelNative2>();
                surfaceConfig.platform.windows.swap_chain_panel = nativePanel.get();
            }
            catch (...)
            {
                // If native panel interop is unavailable, continue without it.
                surfaceConfig.platform.windows.swap_chain_panel = nullptr;
            }
        }
        surfaceConfig.userdata = this;
        const double initialScale =
            (_swapChainPanel && _swapChainPanel.CompositionScaleX() > 0.0)
                ? _swapChainPanel.CompositionScaleX()
                : static_cast<double>(GetDpiForWindow(_ownerWindow)) /
                      static_cast<double>(USER_DEFAULT_SCREEN_DPI);
        surfaceConfig.scale_factor = initialScale;

        DWORD surfaceExceptionCode = 0;
        _ghosttySurface = TryCreateGhosttySurface(_ghosttyApp, &surfaceConfig, &surfaceExceptionCode);
        if (surfaceExceptionCode != 0)
        {
            if (HostTraceEnabled())
            {
                std::cerr << "[host] runtime_init ghostty_surface_new raised SEH 0x"
                          << std::hex << std::uppercase << surfaceExceptionCode
                          << std::dec << std::nouppercase << std::endl;
            }
            std::wstringstream ss;
            ss << L"Ghostty runtime init failed.\nStage: ghostty_surface_new\n";
            ss << L"Result: SEH 0x" << std::hex << std::uppercase << surfaceExceptionCode;
            _lastError = ss.str();

            // After stack overflow (0xC00000FD), additional teardown work can
            // itself fault. Keep the failure path minimal and avoid re-entry.
            _ghosttySurface = nullptr;
            return false;
        }

        if (!_ghosttySurface)
        {
            if (HostTraceEnabled()) std::cerr << "[host] runtime_init failed at ghostty_surface_new (null surface)" << std::endl;
            _lastError = L"Ghostty runtime init failed.\nStage: ghostty_surface_new\nResult: null surface";
            _ShutdownGhosttyRuntime();
            return false;
        }
        if (HostTraceEnabled()) std::cerr << "[host] runtime_init surface created ptr=" << _ghosttySurface << std::endl;

        const auto diagnostics = ghostty_config_diagnostics_count(_ghosttyConfig);
        if (diagnostics > 0)
        {
            std::wstringstream ss;
            ss << L"Status: Runtime initialized with " << diagnostics
               << L" config diagnostics";
            _SetStatus(ss.str());
        }

        return true;
    }
    catch (const std::exception& ex)
    {
        if (HostTraceEnabled())
        {
            std::cerr << "[host] runtime_init exception at stage: "
                      << winrt::to_string(winrt::hstring{ stage })
                      << std::endl;
        }
        std::wstringstream ss;
        ss << L"Ghostty runtime init failed.\n";
        ss << L"Stage: " << stage << L"\n";
        ss << L"std::exception: " << to_hstring(ex.what()).c_str();
        _lastError = ss.str();
        _ShutdownGhosttyRuntime();
        return false;
    }
    catch (...)
    {
        if (HostTraceEnabled())
        {
            std::cerr << "[host] runtime_init unknown exception at stage: "
                      << winrt::to_string(winrt::hstring{ stage })
                      << std::endl;
        }
        std::wstringstream ss;
        ss << L"Ghostty runtime init failed.\n";
        ss << L"Stage: " << stage << L"\n";
        ss << L"Unknown exception";
        _lastError = ss.str();
        _ShutdownGhosttyRuntime();
        return false;
    }
}

void GhosttyTerminalSurfaceV2::_ShutdownGhosttyRuntime() noexcept
{
    if (_ghosttySurface)
    {
        ghostty_surface_free(_ghosttySurface);
        _ghosttySurface = nullptr;
    }

    if (_ghosttyApp)
    {
        ghostty_app_free(_ghosttyApp);
        _ghosttyApp = nullptr;
    }

    if (_ghosttyConfig)
    {
        ghostty_config_free(_ghosttyConfig);
        _ghosttyConfig = nullptr;
    }

    _runtimeTickScheduled.store(false);
    _runtimeInitialized = false;
    _runtimeInitDeferred = false;
}

void GhosttyTerminalSurfaceV2::_ScheduleRuntimeTick() noexcept
{
    if (!_ownerWindow)
    {
        return;
    }

    if (!_runtimeTickScheduled.exchange(true))
    {
        PostMessageW(_ownerWindow, GhosttyWakeupMessage, 0, 0);
    }
}

ghostty_input_mods_e GhosttyTerminalSurfaceV2::_CurrentMods() const noexcept
{
    uint32_t mods = GHOSTTY_MODS_NONE;

    if (GetKeyState(VK_SHIFT) & 0x8000) mods |= GHOSTTY_MODS_SHIFT;
    if (GetKeyState(VK_CONTROL) & 0x8000) mods |= GHOSTTY_MODS_CTRL;
    if (GetKeyState(VK_MENU) & 0x8000) mods |= GHOSTTY_MODS_ALT;
    if (GetKeyState(VK_LWIN) & 0x8000 || GetKeyState(VK_RWIN) & 0x8000) mods |= GHOSTTY_MODS_SUPER;
    if (GetKeyState(VK_CAPITAL) & 0x0001) mods |= GHOSTTY_MODS_CAPS;
    if (GetKeyState(VK_NUMLOCK) & 0x0001) mods |= GHOSTTY_MODS_NUM;
    if (GetKeyState(VK_RSHIFT) & 0x8000) mods |= GHOSTTY_MODS_SHIFT_RIGHT;
    if (GetKeyState(VK_RCONTROL) & 0x8000) mods |= GHOSTTY_MODS_CTRL_RIGHT;
    if (GetKeyState(VK_RMENU) & 0x8000) mods |= GHOSTTY_MODS_ALT_RIGHT;

    return static_cast<ghostty_input_mods_e>(mods);
}

bool GhosttyTerminalSurfaceV2::_SendKeyToGhostty(
    uint32_t keycode,
    bool keyDown,
    const char* text,
    uint32_t unshiftedCodepoint) noexcept
{
    if (!_ghosttyApp)
    {
        if (HostTraceEnabled())
        {
            std::cerr << "[host] key drop: ghostty app is null (keycode=" << keycode
                      << ", down=" << (keyDown ? 1 : 0) << ")" << std::endl;
        }
        return false;
    }

    ghostty_input_key_s ev{};
    ev.action = keyDown ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE;
    ev.mods = _CurrentMods();
    ev.consumed_mods = GHOSTTY_MODS_NONE;
    ev.keycode = keycode;
    ev.text = text;
    ev.unshifted_codepoint = unshiftedCodepoint;
    ev.composing = false;
    if (_ghosttySurface)
    {
        if (HostTraceEnabled())
        {
            std::cerr << "[host] key -> ghostty_surface_key (keycode=" << keycode
                      << ", down=" << (keyDown ? 1 : 0) << ")" << std::endl;
        }
        return ghostty_surface_key(_ghosttySurface, ev);
    }

    if (HostTraceEnabled())
    {
        std::cerr << "[host] key -> ghostty_app_key (keycode=" << keycode
                  << ", down=" << (keyDown ? 1 : 0) << ")" << std::endl;
    }
    return ghostty_app_key(_ghosttyApp, ev);
}

void GhosttyTerminalSurfaceV2::_RuntimeWakeupCallback(void* userdata)
{
    auto* self = static_cast<GhosttyTerminalSurfaceV2*>(userdata);
    if (!self)
    {
        return;
    }

    self->_ScheduleRuntimeTick();
}

bool GhosttyTerminalSurfaceV2::_RuntimeActionCallback(ghostty_app_t app, ghostty_target_s target, ghostty_action_s action)
{
    (void)target;
    (void)action;

    auto* self = static_cast<GhosttyTerminalSurfaceV2*>(ghostty_app_userdata(app));
    if (!self)
    {
        return true;
    }

    // Accept actions and keep driving the app loop so state stays coherent.
    self->_ScheduleRuntimeTick();
    return true;
}

bool GhosttyTerminalSurfaceV2::_RuntimeReadClipboardCallback(void*, ghostty_clipboard_e, void*)
{
    return false;
}

void GhosttyTerminalSurfaceV2::_RuntimeConfirmReadClipboardCallback(void*, const char*, void*, ghostty_clipboard_request_e)
{
}

void GhosttyTerminalSurfaceV2::_RuntimeWriteClipboardCallback(void*, ghostty_clipboard_e, const ghostty_clipboard_content_s*, size_t, bool)
{
}

void GhosttyTerminalSurfaceV2::_RuntimeCloseSurfaceCallback(void* userdata, bool)
{
    auto* self = static_cast<GhosttyTerminalSurfaceV2*>(userdata);
    if (!self)
    {
        return;
    }

    self->_ScheduleRuntimeTick();
}

void GhosttyTerminalSurfaceV2::_SetStatus(const std::wstring& message) noexcept
{
    if (_statusText)
    {
        _statusText.Text(hstring{ message });
    }
}

void GhosttyTerminalSurfaceV2::_UpdateVersion() noexcept
{
    if (!_versionText)
    {
        return;
    }

    std::string versionUtf8;
    const ghostty_info_s info = ghostty_info();
    versionUtf8.assign(info.version, info.version_len);
    _versionText.Text(L"libghostty: " + (versionUtf8.empty() ? hstring{ L"(unavailable)" } : to_hstring(versionUtf8)));
}

void GhosttyTerminalSurfaceV2::_WireInputHandlers() noexcept
{
    _root.CharacterReceived([this](const IInspectable&, const CharacterReceivedRoutedEventArgs& e) {
        _OnCharacter(e);
    });
    _root.KeyDown([this](const IInspectable&, const KeyRoutedEventArgs& e) {
        _OnKey(e, true);
    });
    _root.KeyUp([this](const IInspectable&, const KeyRoutedEventArgs& e) {
        _OnKey(e, false);
    });
    _root.PointerPressed([this](const IInspectable&, const PointerRoutedEventArgs& e) {
        _OnPointerPressed(e);
    });
    _root.PointerMoved([this](const IInspectable&, const PointerRoutedEventArgs& e) {
        _OnPointerMoved(e);
    });
    _root.PointerReleased([this](const IInspectable&, const PointerRoutedEventArgs& e) {
        _OnPointerReleased(e);
    });
    _root.PointerWheelChanged([this](const IInspectable&, const PointerRoutedEventArgs& e) {
        _OnMouseWheel(e);
    });
    _root.GotFocus([this](const IInspectable&, const RoutedEventArgs&) {
        _OnFocusChanged(true);
    });
    _root.LostFocus([this](const IInspectable&, const RoutedEventArgs&) {
        _OnFocusChanged(false);
    });
}

void GhosttyTerminalSurfaceV2::_OnCharacter(const CharacterReceivedRoutedEventArgs& e) noexcept
{
    const uint32_t codepoint = static_cast<uint32_t>(e.Character());
    const std::string text = Utf8FromCodepoint(codepoint);
    const auto keyStatus = e.KeyStatus();
    const bool handled = _SendKeyToGhostty(keyStatus.ScanCode, true, text.empty() ? nullptr : text.c_str(), codepoint);

    std::wstringstream ss;
    ss << L"Status: Character U+" << std::hex << std::uppercase << codepoint
       << L" scan=" << std::dec << keyStatus.ScanCode
       << L" ghostty=" << (handled ? L"handled" : L"pass");
    _SetStatus(ss.str());
    e.Handled(handled);
}

void GhosttyTerminalSurfaceV2::_OnKey(const KeyRoutedEventArgs& e, bool keyDown) noexcept
{
    const auto keyStatus = e.KeyStatus();
    const bool handled = _SendKeyToGhostty(keyStatus.ScanCode, keyDown);
    _SetStatus(L"Status: " + DescribeKeyEvent(e, keyDown) + L" ghostty=" + (handled ? std::wstring{ L"handled" } : std::wstring{ L"pass" }));
    e.Handled(handled);
}

void GhosttyTerminalSurfaceV2::_OnPointerPressed(const PointerRoutedEventArgs& e) noexcept
{
    const auto point = e.GetCurrentPoint(_root);
    std::wstringstream ss;
    ss << L"Status: PointerPressed x=" << point.Position().X << L" y=" << point.Position().Y;
    _SetStatus(ss.str());
}

void GhosttyTerminalSurfaceV2::_OnPointerMoved(const PointerRoutedEventArgs& e) noexcept
{
    const auto point = e.GetCurrentPoint(_root);
    std::wstringstream ss;
    ss << L"Status: PointerMoved x=" << point.Position().X << L" y=" << point.Position().Y;
    _SetStatus(ss.str());
}

void GhosttyTerminalSurfaceV2::_OnPointerReleased(const PointerRoutedEventArgs& e) noexcept
{
    const auto point = e.GetCurrentPoint(_root);
    std::wstringstream ss;
    ss << L"Status: PointerReleased x=" << point.Position().X << L" y=" << point.Position().Y;
    _SetStatus(ss.str());
}

void GhosttyTerminalSurfaceV2::_OnMouseWheel(const PointerRoutedEventArgs& e) noexcept
{
    const auto point = e.GetCurrentPoint(_root);
    std::wstringstream ss;
    ss << L"Status: PointerWheel delta=" << point.Properties().MouseWheelDelta()
       << L" x=" << point.Position().X
       << L" y=" << point.Position().Y;
    _SetStatus(ss.str());
    e.Handled(true);
}

void GhosttyTerminalSurfaceV2::_OnFocusChanged(bool focused) noexcept
{
    if (_ghosttySurface)
    {
        ghostty_surface_set_focus(_ghosttySurface, focused);
    }
    else if (_ghosttyApp)
    {
        ghostty_app_set_focus(_ghosttyApp, focused);
    }

    _SetStatus(focused ? L"Status: Focused" : L"Status: Unfocused");
}
