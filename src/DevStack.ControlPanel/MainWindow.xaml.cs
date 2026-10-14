using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using DevStack.Core;

namespace DevStack.ControlPanel;

public partial class MainWindow : Window
{
    private static readonly Brush RunningBrush = new SolidColorBrush(Color.FromRgb(2, 122, 72));
    private static readonly Brush StoppedBrush = new SolidColorBrush(Color.FromRgb(180, 35, 24));
    private readonly StackController controller;
    private readonly MariaDbPasswordManager passwordManager;
    private readonly PhpConfigurationManager phpConfiguration;

    public MainWindow()
    {
        InitializeComponent();
        var paths = StackPaths.FromApplicationDirectory();
        var options = new StackOptions();
        controller = new StackController(paths, options);
        passwordManager = new MariaDbPasswordManager(paths, options);
        phpConfiguration = new PhpConfigurationManager(paths);
        controller.OutputReceived += (_, line) => Dispatcher.Invoke(() => AppendLog(line));
        controller.StatusChanged += (_, _) => Dispatcher.Invoke(UpdateStatus);
        VersionSummary.Text = LoadVersionSummary(paths);
        UpdateStatus();
    }

    private static string LoadVersionSummary(StackPaths paths)
    {
        var manifestPath = Path.Combine(paths.RuntimeRoot, "manifest", "components.json");
        if (!File.Exists(manifestPath))
        {
            return "Apache · PHP · MariaDB";
        }

        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(manifestPath));
            var versions = document.RootElement.GetProperty("components")
                .EnumerateArray()
                .Where(component => component.GetProperty("name").GetString() is "apache" or "php" or "mariadb")
                .ToDictionary(
                    component => component.GetProperty("name").GetString()!,
                    component => component.GetProperty("version").GetString() ?? "unknown");

            return $"Apache {versions.GetValueOrDefault("apache", "unknown")} · " +
                $"PHP {versions.GetValueOrDefault("php", "unknown")} · " +
                $"MariaDB {versions.GetValueOrDefault("mariadb", "unknown")}";
        }
        catch (Exception)
        {
            return "Apache · PHP · MariaDB";
        }
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

    private async void Quit_Click(object sender, RoutedEventArgs e)
    {
        QuitButton.IsEnabled = false;
        StartButton.IsEnabled = false;
        StopButton.IsEnabled = false;
        try
        {
            if (controller.IsApacheRunning || controller.IsMariaDbRunning)
            {
                await controller.StopAllAsync();
            }

            Close();
        }
        finally
        {
            QuitButton.IsEnabled = true;
        }
    }

    private void RepositoryLink_Click(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo("https://github.com/jtylek/devstack-windows") { UseShellExecute = true });

    private void OpenBrowser_Click(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo("http://127.0.0.1:8080") { UseShellExecute = true });

    private void OpenPhpMyAdmin_Click(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo("http://127.0.0.1:8080/phpmyadmin") { UseShellExecute = true });

    private void StartApache_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            controller.StartApacheOnly();
            AppendLog("Apache started.");
        }
        catch (Exception exception)
        {
            AppendLog($"Apache start failed: {exception.Message}");
            MessageBox.Show(this, exception.Message, "Apache could not start", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            UpdateStatus();
        }
    }

    private void StartMariaDb_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            controller.StartMariaDbOnly();
            AppendLog("MariaDB started.");
        }
        catch (Exception exception)
        {
            AppendLog($"MariaDB start failed: {exception.Message}");
            MessageBox.Show(this, exception.Message, "MariaDB could not start", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            UpdateStatus();
        }
    }

    private async void StopApache_Click(object sender, RoutedEventArgs e)
    {
        StopApacheButton.IsEnabled = false;
        try
        {
            await controller.StopApacheAsync();
        }
        finally
        {
            UpdateStatus();
        }
    }

    private async void StopMariaDb_Click(object sender, RoutedEventArgs e)
    {
        StopMariaDbButton.IsEnabled = false;
        try
        {
            await controller.StopMariaDbAsync();
        }
        finally
        {
            UpdateStatus();
        }
    }

    private async void PhpExtensions_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var dialog = new PhpExtensionsWindow(phpConfiguration.GetExtensionStates()) { Owner = this };
            if (dialog.ShowDialog() != true)
            {
                return;
            }

            phpConfiguration.SaveExtensionStates(dialog.States);
            AppendLog("PHP extension settings saved.");
            await OfferRestartAsync();
        }
        catch (Exception exception)
        {
            MessageBox.Show(this, exception.Message, "Could not save PHP extensions", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async void OpcacheSettings_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var dialog = new OpcacheSettingsWindow(phpConfiguration.GetOpcacheSettings()) { Owner = this };
            if (dialog.ShowDialog() != true)
            {
                return;
            }

            phpConfiguration.SaveOpcacheSettings(dialog.Settings);
            AppendLog("OPcache settings saved.");
            await OfferRestartAsync();
        }
        catch (Exception exception)
        {
            MessageBox.Show(this, exception.Message, "Could not save OPcache settings", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async Task OfferRestartAsync()
    {
        if (!controller.IsApacheRunning)
        {
            return;
        }

        var restart = MessageBox.Show(this, "PHP settings are saved. Restart Apache now to apply them?", "Restart required", MessageBoxButton.YesNo, MessageBoxImage.Question);
        if (restart != MessageBoxResult.Yes)
        {
            return;
        }

        StartButton.IsEnabled = false;
        StopButton.IsEnabled = false;
        try
        {
            await controller.RestartApacheAsync();
            AppendLog("Apache restarted with the new PHP settings.");
        }
        catch (Exception exception)
        {
            AppendLog($"Restart failed: {exception.Message}");
            MessageBox.Show(this, exception.Message, "Apache could not restart", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            UpdateStatus();
        }
    }

    private void ChangeRootPassword_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new PasswordChangeWindow { Owner = this };
        if (dialog.ShowDialog() != true)
        {
            return;
        }

        ChangeRootPasswordButton.IsEnabled = false;
        try
        {
            passwordManager.ChangeRootPassword(dialog.NewPassword);
            AppendLog("MariaDB root password changed.");
            MessageBox.Show(this, "The MariaDB root password was changed successfully.", "Password updated", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception exception)
        {
            AppendLog($"Root password change failed: {exception.Message}");
            MessageBox.Show(this, exception.Message, "Could not change root password", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            UpdateStatus();
        }
    }

    private void UpdateStatus()
    {
        SetStatus(ApacheStatus, controller.IsApacheRunning);
        SetStatus(MariaDbStatus, controller.IsMariaDbRunning);
        StartButton.IsEnabled = !controller.IsApacheRunning || !controller.IsMariaDbRunning;
        StopButton.IsEnabled = controller.IsApacheRunning || controller.IsMariaDbRunning;
        StartApacheButton.IsEnabled = !controller.IsApacheRunning;
        StopApacheButton.IsEnabled = controller.IsApacheRunning;
        StartMariaDbButton.IsEnabled = !controller.IsMariaDbRunning;
        StopMariaDbButton.IsEnabled = controller.IsMariaDbRunning;
        OpenBrowserButton.IsEnabled = controller.IsApacheRunning;
        OpenPhpMyAdminButton.IsEnabled = controller.IsApacheRunning;
        ChangeRootPasswordButton.IsEnabled = controller.IsMariaDbRunning;
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
