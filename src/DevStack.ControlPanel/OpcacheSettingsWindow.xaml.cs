using System.Windows;
using DevStack.Core;

namespace DevStack.ControlPanel;

public partial class OpcacheSettingsWindow : Window
{
    public OpcacheSettingsWindow(OpcacheSettings settings)
    {
        InitializeComponent();
        EnabledBox.IsChecked = settings.Enabled;
        MemoryBox.Text = settings.MemoryConsumptionMb.ToString();
        FilesBox.Text = settings.MaxAcceleratedFiles.ToString();
        RevalidateBox.Text = settings.RevalidateFrequencySeconds.ToString();
    }

    public OpcacheSettings Settings { get; private set; } = new();

    private void Apply_Click(object sender, RoutedEventArgs e)
    {
        if (!int.TryParse(MemoryBox.Text, out var memory) ||
            !int.TryParse(FilesBox.Text, out var files) ||
            !int.TryParse(RevalidateBox.Text, out var revalidate) ||
            memory < 8 || memory > 4096 || files < 100 || files > 1000000 || revalidate < 0 || revalidate > 3600)
        {
            MessageBox.Show(this, "Enter valid values: memory 8–4096 MB, files 100–1,000,000, revalidation 0–3600 seconds.", "Invalid OPcache settings", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        Settings = new OpcacheSettings(EnabledBox.IsChecked == true, memory, files, revalidate);
        DialogResult = true;
    }
}
