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
        InternedStringsBox.Text = settings.InternedStringsBufferMb.ToString();
        FilesBox.Text = settings.MaxAcceleratedFiles.ToString();
        RevalidateBox.Text = settings.RevalidateFrequencySeconds.ToString();
        RealpathBox.Text = settings.RealpathCacheTtlSeconds.ToString();
        AssertionsBox.Text = settings.ZendAssertions.ToString();
        DisplayErrorsBox.IsChecked = settings.DisplayErrors;
    }

    public OpcacheSettings Settings { get; private set; } = new();

    private void Apply_Click(object sender, RoutedEventArgs e)
    {
        if (!int.TryParse(MemoryBox.Text, out var memory) ||
            !int.TryParse(InternedStringsBox.Text, out var internedStrings) ||
            !int.TryParse(FilesBox.Text, out var files) ||
            !int.TryParse(RevalidateBox.Text, out var revalidate) ||
            !int.TryParse(RealpathBox.Text, out var realpath) ||
            !int.TryParse(AssertionsBox.Text, out var assertions) ||
            memory < 8 || memory > 4096 || internedStrings < 1 || internedStrings > 4096 ||
            files < 100 || files > 1000000 || revalidate < 0 || revalidate > 3600 ||
            realpath < 0 || realpath > 86400 || assertions is not (-1 or 0 or 1))
        {
            MessageBox.Show(this, "Enter valid values: memory 8–4096 MB, interned strings 1–4096 MB, files 100–1,000,000, revalidation 0–3600 seconds, realpath TTL 0–86400 seconds, and zend.assertions -1, 0, or 1.", "Invalid OPcache settings", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        Settings = new OpcacheSettings(EnabledBox.IsChecked == true, memory, internedStrings, files, revalidate, realpath, assertions, DisplayErrorsBox.IsChecked == true);
        DialogResult = true;
    }
}
