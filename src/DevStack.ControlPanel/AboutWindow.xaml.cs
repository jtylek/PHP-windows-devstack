using System.Diagnostics;
using System.Windows;

namespace DevStack.ControlPanel;

public partial class AboutWindow : Window
{
    public AboutWindow() => InitializeComponent();

    private void RepositoryLink_Click(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo("https://github.com/jtylek/PHP-windows-devstack") { UseShellExecute = true });
}
