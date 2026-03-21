#pragma once

#include <windows.h>

#ifdef GetCurrentTime
#undef GetCurrentTime
#endif

#include <atomic>
#include <string>

#include "GhosttyApiShim.h"

#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.UI.Xaml.h>
#include <winrt/Windows.UI.Xaml.Controls.h>
#include <winrt/Windows.UI.Xaml.Input.h>

class GhosttyTerminalSurfaceV2
{
public:
    static constexpr UINT GhosttyWakeupMessage = WM_APP + 0x52;

    bool Initialize(HWND ownerWindow) noexcept;
    void Shutdown() noexcept;
    bool PumpRuntimeTick() noexcept;
    const std::wstring& LastError() const noexcept;

    winrt::Windows::UI::Xaml::UIElement Root() const noexcept;
    void FocusTerminal() noexcept;
    void SetSurfaceMetrics(uint32_t widthPx, uint32_t heightPx, double scaleFactor) noexcept;

    bool OnDirectKeyEvent(uint32_t vkey, uint8_t scanCode, bool down) noexcept;
    bool OnMouseWheel(const winrt::Windows::Foundation::Point& location,
                      const winrt::Windows::Foundation::Point& delta,
                      bool leftButtonDown,
                      bool middleButtonDown,
                      bool rightButtonDown) noexcept;

    void AttachSwapChainHandle(HANDLE swapChainHandle) noexcept;

private:
    bool _InitializeGhosttyRuntime() noexcept;
    void _ShutdownGhosttyRuntime() noexcept;
    void _ScheduleRuntimeTick() noexcept;
    ghostty_input_mods_e _CurrentMods() const noexcept;
    bool _SendKeyToGhostty(uint32_t keycode, bool keyDown, const char* text = nullptr, uint32_t unshiftedCodepoint = 0) noexcept;

    static void _RuntimeWakeupCallback(void* userdata);
    static bool _RuntimeActionCallback(ghostty_app_t app, ghostty_target_s target, ghostty_action_s action);
    static bool _RuntimeReadClipboardCallback(void* userdata, ghostty_clipboard_e clipboard, void* request);
    static void _RuntimeConfirmReadClipboardCallback(void* userdata, const char* text, void* request, ghostty_clipboard_request_e requestType);
    static void _RuntimeWriteClipboardCallback(void* userdata, ghostty_clipboard_e clipboard, const ghostty_clipboard_content_s* contents, size_t count, bool confirmed);
    static void _RuntimeCloseSurfaceCallback(void* userdata, bool processAlive);

    void _SetStatus(const std::wstring& message) noexcept;
    void _UpdateVersion() noexcept;
    void _WireInputHandlers() noexcept;

    void _OnCharacter(const winrt::Windows::UI::Xaml::Input::CharacterReceivedRoutedEventArgs& e) noexcept;
    void _OnKey(const winrt::Windows::UI::Xaml::Input::KeyRoutedEventArgs& e, bool keyDown) noexcept;
    void _OnPointerPressed(const winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs& e) noexcept;
    void _OnPointerMoved(const winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs& e) noexcept;
    void _OnPointerReleased(const winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs& e) noexcept;
    void _OnMouseWheel(const winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs& e) noexcept;
    void _OnFocusChanged(bool focused) noexcept;

    HWND _ownerWindow{ nullptr };
    winrt::Windows::UI::Xaml::Controls::UserControl _root{ nullptr };
    winrt::Windows::UI::Xaml::Controls::Grid _layout{ nullptr };
    winrt::Windows::UI::Xaml::Controls::SwapChainPanel _swapChainPanel{ nullptr };
    winrt::Windows::UI::Xaml::Controls::TextBlock _versionText{ nullptr };
    winrt::Windows::UI::Xaml::Controls::TextBlock _statusText{ nullptr };
    ghostty_config_t _ghosttyConfig{ nullptr };
    ghostty_app_t _ghosttyApp{ nullptr };
    ghostty_surface_t _ghosttySurface{ nullptr };
    std::atomic_bool _runtimeTickScheduled{ false };
    std::wstring _lastError{};
};
