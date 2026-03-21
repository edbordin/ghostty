#include "WinUiContent.h"

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.UI.Xaml.Controls.h>

using namespace winrt;
using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::UI::Xaml;
using namespace winrt::Windows::UI::Xaml::Controls;

UIElement CreateGhosttyRootContent(const hstring& versionText)
{
    StackPanel panel;
    panel.Padding(ThicknessHelper::FromUniformLength(16.0));

    TextBlock title;
    title.Text(L"Ghostty Windows Host");
    title.FontSize(22.0);

    TextBlock subtitle;
    subtitle.Text(L"Win32 + WinUI (XAML Island) skeleton");
    subtitle.Opacity(0.8);

    TextBlock version;
    version.Text(L"libghostty: " + versionText);
    version.TextWrapping(TextWrapping::Wrap);

    Button action;
    action.Content(box_value(L"Host Initialized"));
    action.IsEnabled(false);

    panel.Children().Append(title);
    panel.Children().Append(subtitle);
    panel.Children().Append(version);
    panel.Children().Append(action);

    return panel;
}
