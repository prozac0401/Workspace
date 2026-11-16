using System;
using System.Security;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;

namespace ExcelPasswordSafe
{
    public sealed class PasswordField : StackPanel
    {
        readonly PasswordBox masked = new PasswordBox();
        readonly TextBox revealed = new TextBox();
        readonly TextBlock error = new TextBlock();
        bool syncing;
        public event EventHandler ValueChanged;
        public PasswordField(string label)
        {
            Margin = new Thickness(0, 0, 0, 12);
            Children.Add(new Label { Content = label, Target = masked, FontSize = 12, Foreground = new SolidColorBrush(Color.FromRgb(67, 80, 104)), Padding = new Thickness(0), Margin = new Thickness(0, 0, 0, 5) });
            var panel = new Grid(); Children.Add(panel);
            masked.MinHeight = revealed.MinHeight = 40;
            revealed.Visibility = Visibility.Collapsed;
            AutomationProperties.SetName(masked, label); AutomationProperties.SetName(revealed, label + " · 표시 중");
            panel.Children.Add(masked); panel.Children.Add(revealed);
            error.FontSize = 11; error.Foreground = Brushes.Firebrick; error.TextWrapping = TextWrapping.Wrap;
            error.Margin = new Thickness(0, 4, 0, 0); error.Visibility = Visibility.Collapsed;
            AutomationProperties.SetLiveSetting(error, AutomationLiveSetting.Polite); Children.Add(error);
            masked.PasswordChanged += delegate
            {
                if (syncing) return;
                if (revealed.Visibility == Visibility.Visible) { syncing = true; revealed.Text = masked.Password; syncing = false; }
                Changed();
            };
            revealed.TextChanged += delegate
            {
                if (syncing) return;
                syncing = true; masked.Password = revealed.Text; syncing = false; Changed();
            };
        }
        void Changed() { SetError(null); var handler = ValueChanged; if (handler != null) handler(this, EventArgs.Empty); }
        public SecureString Secret { get { return masked.SecurePassword; } }
        public int Length { get { using (var value = masked.SecurePassword) return value.Length; } }
        public bool IsRevealed { get { return revealed.Visibility == Visibility.Visible; } }
        public void Reveal(bool value)
        {
            syncing = true;
            if (value) revealed.Text = masked.Password;
            else revealed.Clear();
            revealed.Visibility = value ? Visibility.Visible : Visibility.Collapsed;
            masked.Visibility = value ? Visibility.Collapsed : Visibility.Visible;
            syncing = false;
        }
        public void Clear() { Reveal(false); masked.Clear(); SetError(null); }
        public void FocusInput() { if (IsRevealed) revealed.Focus(); else masked.Focus(); }
        public void SetError(string message)
        {
            error.Text = message ?? ""; error.Visibility = String.IsNullOrEmpty(message) ? Visibility.Collapsed : Visibility.Visible;
            masked.BorderBrush = revealed.BorderBrush = String.IsNullOrEmpty(message) ? new SolidColorBrush(Color.FromRgb(213, 221, 234)) : Brushes.Firebrick;
        }
        public void SetSmokePassword(string value) { masked.Password = value; }
    }
}
