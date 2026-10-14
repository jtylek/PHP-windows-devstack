using System.Diagnostics;
using System.Windows;
using System.Windows.Media;
using DevStack.Core;

namespace DevStack.ControlPanel;

public partial class MainWindow : Window
{
    private static readonly Brush RunningBrush = new SolidColorBrush(Color.FromRgb(2, 122, 72));
    private static readonly Brush StoppedBrush = new SolidColorBrush(Color.FromRgb(180, 35, 24));
    private readonly StackController controller;

    public MainWindow()
    {
        InitializeComponent();
        controller = new StackController(StackPaths.FromApplicationDirectory(), new StackOptions());
        controller.OutputReceived += (_, line) => Dispatcher.Invoke(() => AppendLog(line));
        controller.StatusChanged += (_, _) => Dispatcher.Invoke(UpdateStatus);
        UpdateStatus();
    }

    private void StartAll_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            controller.StartAll();
            AppendLog("DevStack started.");
        }
        catch (Exception exception)
        {
            AppendLog($"Start failed: {exception.Message}");
            MessageBox.Show(this, exception.Message, "DevStack could not start", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            UpdateStatus();
        }
    }

    private async void StopAll_Click(object sender, RoutedEventArgs e)
    {
        StopButton.IsEnabled = false;
        try
        {
            await controller.StopAllAsync();
            AppendLog("DevStack stopped.");
        }
        finally
        {
            StopButton.IsEnabled = true;
            UpdateStatus();
        }
    }

    private void OpenBrowser_Click(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo("http://127.0.0.1:8080") { UseShellExecute = true });

    private void UpdateStatus()
    {
        SetStatus(ApacheStatus, controller.IsApacheRunning);
        SetStatus(MariaDbStatus, controller.IsMariaDbRunning);
        StartButton.IsEnabled = !controller.IsApacheRunning && !controller.IsMariaDbRunning;
        StopButton.IsEnabled = controller.IsApacheRunning || controller.IsMariaDbRunning;
    }

    private static void SetStatus(System.Windows.Controls.TextBlock label, bool running)
    {
        label.Text = running ? "Running" : "Stopped";
        label.Foreground = running ? RunningBrush : StoppedBrush;
    }

    private void AppendLog(string message)
    {
        LogOutput.AppendText($"{DateTime.Now:HH:mm:ss} {message}{Environment.NewLine}");
        LogOutput.ScrollToEnd();
    }

    protected override void OnClosed(EventArgs e)
    {
        controller.Dispose();
        base.OnClosed(e);
    }
}
