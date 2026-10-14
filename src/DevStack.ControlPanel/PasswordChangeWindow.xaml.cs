using System.Windows;

namespace DevStack.ControlPanel;

public partial class PasswordChangeWindow : Window
{
    public PasswordChangeWindow()
    {
        InitializeComponent();
        Loaded += (_, _) => NewPasswordBox.Focus();
    }

    public string NewPassword => NewPasswordBox.Password;

    private void SetPassword_Click(object sender, RoutedEventArgs e)
    {
        if (NewPassword.Length < 8)
        {
            MessageBox.Show(this, "The root password must contain at least 8 characters.", "Invalid password", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        if (NewPassword.Contains('\r') || NewPassword.Contains('\n'))
        {
            MessageBox.Show(this, "The root password cannot contain line breaks.", "Invalid password", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        if (!string.Equals(NewPassword, ConfirmPasswordBox.Password, StringComparison.Ordinal))
        {
            MessageBox.Show(this, "The passwords do not match.", "Invalid password", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        DialogResult = true;
    }
}
