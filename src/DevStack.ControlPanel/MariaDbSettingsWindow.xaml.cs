using System.Windows;
using DevStack.Core;

namespace DevStack.ControlPanel;

public partial class MariaDbSettingsWindow : Window
{
    public MariaDbSettingsWindow(MariaDbSettings settings)
    {
        InitializeComponent();
        BufferPoolBox.Text = settings.BufferPoolSizeMb?.ToString() ?? "";
        var memory = MariaDbSettingsManager.GetPhysicalMemoryBytes();
        AutomaticSummary.Text = $"Automatic on this machine: {MariaDbSettingsManager.CalculateAutomaticSizeMb(memory)} MB. " +
            (memory == 0 ? "Physical RAM detection unavailable; using conservative fallback." :
                "Approximately 1/16 of installed RAM, capped at 2048 MB (512 MB on 8 GB, 1024 MB on 16 GB).");
    }

    public MariaDbSettings Settings { get; private set; } = new();

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            int? size = null;
            if (!string.IsNullOrWhiteSpace(BufferPoolBox.Text))
            {
                if (!int.TryParse(BufferPoolBox.Text, out var value))
                    throw new ArgumentException("Enter a whole number of MB or leave the override blank.");
                size = value;
            }
            Settings = new(size);
            MariaDbSettingsManager.Validate(Settings);
            DialogResult = true;
        }
        catch (ArgumentException exception)
        {
            MessageBox.Show(this, exception.Message, "Invalid memory setting", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }
}
