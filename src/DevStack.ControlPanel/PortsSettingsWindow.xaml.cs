using System.Windows;

namespace DevStack.ControlPanel;

public partial class PortsSettingsWindow : Window
{
    public PortsSettingsWindow(int apachePort, int mariaDbPort)
    {
        InitializeComponent();
        ApachePortTextBox.Text = apachePort.ToString();
        MariaDbPortTextBox.Text = mariaDbPort.ToString();
    }

    public int ApachePort { get; private set; }
    public int MariaDbPort { get; private set; }

    private void Apply_Click(object sender, RoutedEventArgs e)
    {
        if (!int.TryParse(ApachePortTextBox.Text, out var apachePort) ||
            !int.TryParse(MariaDbPortTextBox.Text, out var mariaDbPort))
        {
            MessageBox.Show(this, "Enter valid numeric port values.", "Invalid ports", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        ApachePort = apachePort;
        MariaDbPort = mariaDbPort;
        DialogResult = true;
    }

    private void Cancel_Click(object sender, RoutedEventArgs e) => DialogResult = false;
}
