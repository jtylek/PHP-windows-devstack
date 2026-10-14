using System.Collections.ObjectModel;
using System.Windows;
using DevStack.Core;
using Microsoft.Win32;

namespace DevStack.ControlPanel;

public partial class SmtpCaptureWindow : Window
{
    private readonly SmtpCaptureService service;
    private readonly ObservableCollection<SmtpCapturedMessage> messages = new();

    public SmtpCaptureWindow(SmtpCaptureService service)
    {
        InitializeComponent();
        this.service = service;
        MessagesList.ItemsSource = messages;
        service.MessageCaptured += Service_MessageCaptured;
        RefreshMessages();
        UpdateControls();
    }

    private void Service_MessageCaptured(object? sender, string path) => Dispatcher.Invoke(() => RefreshMessages());

    private void Start_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            service.Start();
            UpdateControls();
        }
        catch (Exception exception)
        {
            MessageBox.Show(this, exception.Message, "Could not start SMTP capture", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async void Stop_Click(object sender, RoutedEventArgs e)
    {
        await service.StopAsync();
        UpdateControls();
    }

    private void Refresh_Click(object sender, RoutedEventArgs e) => RefreshMessages();

    private void RefreshMessages()
    {
        var selectedPath = (MessagesList.SelectedItem as SmtpCapturedMessage)?.Path;
        messages.Clear();
        foreach (var message in service.GetMessages())
        {
            messages.Add(message);
        }
        if (selectedPath is not null)
        {
            MessagesList.SelectedItem = messages.FirstOrDefault(message => message.Path == selectedPath);
        }
        UpdateControls();
    }

    private void MessagesList_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        if (MessagesList.SelectedItem is SmtpCapturedMessage message)
        {
            try { MessageContent.Text = service.ReadMessage(message); }
            catch (IOException) { MessageContent.Text = "The message is no longer available."; }
        }
        else
        {
            MessageContent.Clear();
        }
    }

    private void DeleteSelected_Click(object sender, RoutedEventArgs e)
    {
        if (MessagesList.SelectedItem is not SmtpCapturedMessage message)
        {
            return;
        }
        service.DeleteMessage(message);
        RefreshMessages();
    }

    private void DeleteAll_Click(object sender, RoutedEventArgs e)
    {
        if (messages.Count == 0 || MessageBox.Show(this, "Delete all captured messages?", "Confirm deletion", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes)
        {
            return;
        }
        service.DeleteAllMessages();
        RefreshMessages();
    }

    private void Export_Click(object sender, RoutedEventArgs e)
    {
        if (MessagesList.SelectedItem is not SmtpCapturedMessage message)
        {
            return;
        }
        var dialog = new SaveFileDialog { Filter = "Email message (*.eml)|*.eml", FileName = message.FileName };
        if (dialog.ShowDialog(this) == true)
        {
            File.Copy(message.Path, dialog.FileName, overwrite: true);
        }
    }

    private void UpdateControls()
    {
        StartButton.IsEnabled = !service.IsRunning;
        StopButton.IsEnabled = service.IsRunning;
        Title = service.IsRunning ? "SMTP Mail Capture - Listening on port 25" : "SMTP Mail Capture - Stopped";
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();

    protected override void OnClosed(EventArgs e)
    {
        service.MessageCaptured -= Service_MessageCaptured;
        base.OnClosed(e);
    }
}
