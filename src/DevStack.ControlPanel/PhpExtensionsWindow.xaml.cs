using System.Windows;
using System.Windows.Controls;
using DevStack.Core;

namespace DevStack.ControlPanel;

public partial class PhpExtensionsWindow : Window
{
    private readonly List<(PhpExtensionState State, System.Windows.Controls.CheckBox CheckBox)> entries = [];

    public PhpExtensionsWindow(IEnumerable<PhpExtensionState> states)
    {
        InitializeComponent();
        foreach (var state in states)
        {
            var checkBox = new System.Windows.Controls.CheckBox
            {
                Content = state.Available ? state.Name : $"{state.Name} (not included)",
                IsChecked = state.Enabled,
                IsEnabled = state.Available,
                Margin = new Thickness(0, 0, 0, 10)
            };
            ExtensionsPanel.Children.Add(checkBox);
            entries.Add((state, checkBox));
        }
    }

    public IReadOnlyList<PhpExtensionState> States => entries
        .Select(entry => entry.State with { Enabled = entry.CheckBox.IsChecked == true })
        .ToArray();

    private void Apply_Click(object sender, RoutedEventArgs e) => DialogResult = true;
}
