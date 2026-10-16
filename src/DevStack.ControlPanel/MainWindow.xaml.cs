using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.ComponentModel;
using System.Windows;
using System.Windows.Media;
using Forms = System.Windows.Forms;
using DevStack.Core;

namespace DevStack.ControlPanel;

public partial class MainWindow : Window
{
    private static readonly Brush RunningBrush = new SolidColorBrush(Color.FromRgb(2, 122, 72));
    private static readonly Brush StoppedBrush = new SolidColorBrush(Color.FromRgb(180, 35, 24));
    private readonly StackController controller;
    private readonly StackOptions options;
    private readonly PortSettingsManager portSettings;
    private readonly MariaDbPasswordManager passwordManager;
    private readonly PhpConfigurationManager phpConfiguration;
    private readonly SmtpCaptureService smtpCapture;
    private SmtpCaptureWindow? smtpCaptureWindow;
    private readonly Forms.NotifyIcon trayIcon;
    private bool allowClose;

    public MainWindow()
    {
        InitializeComponent();
        Closing += MainWindow_Closing;
        trayIcon = CreateTrayIcon();
        var paths = StackPaths.FromApplicationDirectory();
        portSettings = new PortSettingsManager(paths);
        options = portSettings.Load();
        controller = new StackController(paths, options);
        passwordManager = new MariaDbPasswordManager(paths, options);
        phpConfiguration = new PhpConfigurationManager(paths);
        smtpCapture = new SmtpCaptureService(paths.SmtpRoot);
        smtpCapture.MessageCaptured += (_, path) => Dispatcher.Invoke(() => AppendLog($"SMTP message captured: {Path.GetFileName(path)}"));
        smtpCapture.StatusChanged += (_, _) => Dispatcher.Invoke(UpdateStatus);
        controller.OutputReceived += (_, line) => Dispatcher.Invoke(() => AppendLog(line));
        controller.StatusChanged += (_, _) => Dispatcher.Invoke(UpdateStatus);
        VersionSummary.Text = LoadVersionSummary(paths);
        UpdateStatus();
        if (controller.IsApacheRunning)
            AppendLog("Detected an existing Apache process from this DevStack installation.");
        if (controller.IsMariaDbRunning)
            AppendLog("Detected an existing MariaDB process from this DevStack installation.");
    }

    private Forms.NotifyIcon CreateTrayIcon()
    {
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Open PHP Windows DevStack", null, (_, _) => RestoreFromTray());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Quit and stop services", null, (_, _) => Quit_Click(this, new RoutedEventArgs()));
        var icon = new Forms.NotifyIcon
        {
            Icon = System.Drawing.SystemIcons.Application,
            Text = "PHP Windows DevStack",
            ContextMenuStrip = menu,
            Visible = false
        };
        icon.DoubleClick += (_, _) => RestoreFromTray();
        return icon;
    }

    private void MainWindow_Closing(object? sender, CancelEventArgs e)
    {
        if (allowClose)
        {
            return;
        }

        e.Cancel = true;
        trayIcon.Visible = true;
        Hide();
        trayIcon.BalloonTipTitle = "PHP Windows DevStack is still running";
        trayIcon.BalloonTipText = "Apache and MariaDB keep running. Choose 'Quit and stop services' in the tray menu to stop them and exit.";
        trayIcon.ShowBalloonTip(4000);
    }

    private void RestoreFromTray()
    {
        trayIcon.Visible = false;
        Show();
        if (WindowState == WindowState.Minimized)
        {
            WindowState = WindowState.Normal;
        }
        Activate();
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

            allowClose = true;
            Close();
        }
        catch (Exception exception)
        {
            AppendLog($"Quit failed: {exception.Message}");
            MessageBox.Show(this, exception.Message, "Could not stop DevStack", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            UpdateStatus();
            QuitButton.IsEnabled = true;
        }
    }

    private void RepositoryLink_Click(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo("https://github.com/jtylek/PHP-windows-devstack") { UseShellExecute = true });

    private void About_Click(object sender, RoutedEventArgs e) =>
        MessageBox.Show(
            this,
            "PHP Windows DevStack is a native, portable Windows development environment for PHP applications.\n\n" +
            "It includes Apache HTTP Server, PHP 8.5, MariaDB, and a desktop control panel.",
            "About PHP Windows DevStack",
            MessageBoxButton.OK,
            MessageBoxImage.Information);

    private void MariaDbSettings_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var manager = new MariaDbSettingsManager(StackPaths.FromApplicationDirectory());
            var dialog = new MariaDbSettingsWindow(manager.Load()) { Owner = this };
            if (dialog.ShowDialog() != true) return;
            manager.Save(dialog.Settings);
            AppendLog("MariaDB memory settings saved. Stop and start MariaDB to apply them; Apache need not restart.");
        }
        catch (Exception exception)
        {
            MessageBox.Show(this, exception.Message, "Could not save MariaDB settings", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void MariaDbErrorLog_Click(object sender, RoutedEventArgs e) => OpenMariaDbLog("mariadb-error.log");
    private void MariaDbSlowLog_Click(object sender, RoutedEventArgs e) => OpenMariaDbLog("mariadb-slow.log");

    private void OpenMariaDbLog(string filename)
    {
        try
        {
            var path = Path.Combine(StackPaths.FromApplicationDirectory().LogRoot, filename);
            if (!File.Exists(path))
            {
                MessageBox.Show(this, "This log does not exist yet. Start MariaDB; slow queries are recorded when they exceed one second.",
                    "MariaDB log", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "notepad.exe"))
                { UseShellExecute = false };
            start.ArgumentList.Add(path);
            using var process = Process.Start(start);
        }
        catch (Exception exception)
        {
            MessageBox.Show(this, exception.Message, "Could not open MariaDB log", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void OpenPowerShell_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            using var process = Process.Start(PhpTerminal.CreateStartInfo(StackPaths.FromApplicationDirectory(), options));
            AppendLog("Opened PowerShell with bundled PHP and PHPDevStack's generated php.ini.");
        }
        catch (Exception exception)
        {
            MessageBox.Show(this, exception.Message, "Could not open PowerShell", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void OpenBrowser_Click(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo($"http://127.0.0.1:{options.HttpPort}") { UseShellExecute = true });

    private void OpenPhpMyAdmin_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            new PhpMyAdminSignOn(StackPaths.FromApplicationDirectory(), options).Launch();
            AppendLog("Opening phpMyAdmin with a one-time local root sign-in.");
        }
        catch (Exception exception)
        {
            AppendLog($"phpMyAdmin sign-in failed: {exception.Message}");
            MessageBox.Show(this, exception.Message, "Could not open phpMyAdmin", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

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

    private void PortsSettings_Click(object sender, RoutedEventArgs e)
    {
        if (controller.IsApacheRunning || controller.IsMariaDbRunning)
        {
            MessageBox.Show(this, "Stop Apache and MariaDB before changing their ports.", "Services must be stopped", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var dialog = new PortsSettingsWindow(options.HttpPort, options.MariaDbPort) { Owner = this };
        if (dialog.ShowDialog() != true)
        {
            return;
        }

        try
        {
            portSettings.Save(options, dialog.ApachePort, dialog.MariaDbPort);
            options.HttpPort = dialog.ApachePort;
            options.MariaDbPort = dialog.MariaDbPort;
            portSettings.UpdatePhpMyAdminPort(options.MariaDbPort);
            AppendLog($"Ports saved: Apache {options.HttpPort}, MariaDB {options.MariaDbPort}.");
            UpdateStatus();
        }
        catch (Exception exception)
        {
            AppendLog($"Port settings were not saved: {exception.Message}");
            MessageBox.Show(this, exception.Message, "Could not change ports", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void SmtpCapture_Click(object sender, RoutedEventArgs e)
    {
        if (smtpCaptureWindow is { IsVisible: true })
        {
            smtpCaptureWindow.Activate();
            return;
        }

        smtpCaptureWindow = new SmtpCaptureWindow(smtpCapture) { Owner = this };
        smtpCaptureWindow.Show();
        UpdateStatus();
    }

    private void StartSmtp_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            smtpCapture.Start();
            AppendLog("SMTP capture started on 127.0.0.1:25.");
        }
        catch (Exception exception)
        {
            AppendLog($"SMTP capture start failed: {exception.Message}");
            MessageBox.Show(this, exception.Message, "SMTP capture could not start", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            UpdateStatus();
        }
    }

    private async void StopSmtp_Click(object sender, RoutedEventArgs e)
    {
        StopSmtpButton.IsEnabled = false;
        try
        {
            await smtpCapture.StopAsync();
            AppendLog("SMTP capture stopped.");
        }
        finally
        {
            UpdateStatus();
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
        ApacheEndpoint.Text = $"127.0.0.1:{options.HttpPort}";
        MariaDbEndpoint.Text = $"127.0.0.1:{options.MariaDbPort}";
        SetStatus(SmtpCardStatus, smtpCapture.IsRunning);
        StartSmtpButton.IsEnabled = !smtpCapture.IsRunning;
        StopSmtpButton.IsEnabled = smtpCapture.IsRunning;
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
        smtpCaptureWindow?.Close();
        smtpCapture.StopAsync().GetAwaiter().GetResult();
        trayIcon.Visible = false;
        trayIcon.Dispose();
        controller.Dispose();
        base.OnClosed(e);
    }
}
