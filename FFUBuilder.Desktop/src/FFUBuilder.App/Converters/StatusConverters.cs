using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;
using FFUBuilder.App.Models;

namespace FFUBuilder.App.Converters;

public class StatusToBrushConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return value switch
        {
            CheckStatus.Passed => new SolidColorBrush(Color.FromRgb(0x2E, 0x7D, 0x32)),   // green
            CheckStatus.Failed => new SolidColorBrush(Color.FromRgb(0xC6, 0x28, 0x28)),   // red
            CheckStatus.Warning => new SolidColorBrush(Color.FromRgb(0xF5, 0x7F, 0x17)),  // amber
            CheckStatus.Running => new SolidColorBrush(Color.FromRgb(0x15, 0x65, 0xC0)),  // blue
            CheckStatus.Skipped => new SolidColorBrush(Color.FromRgb(0x75, 0x75, 0x75)),  // gray
            _ => new SolidColorBrush(Color.FromRgb(0x75, 0x75, 0x75))                      // gray
        };
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

public class StatusToIconConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return value switch
        {
            CheckStatus.Passed => "\u2713",   // checkmark
            CheckStatus.Failed => "\u2717",   // X
            CheckStatus.Warning => "\u26A0",  // warning triangle
            CheckStatus.Running => "\u25CC",  // dotted circle
            CheckStatus.Skipped => "\u25CB",  // circle
            _ => "\u25CB"
        };
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

public class BoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return value is true ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

public class DurationToStringConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is TimeSpan ts && ts.TotalMilliseconds > 0)
            return $"({ts.TotalSeconds:F1}s)";
        return string.Empty;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

public class InverseBoolConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        => value is false;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

public class LogLevelToBrushConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return value switch
        {
            Models.LogLevel.Error => new SolidColorBrush(Color.FromRgb(0xC6, 0x28, 0x28)),   // red
            Models.LogLevel.Warning => new SolidColorBrush(Color.FromRgb(0xF5, 0x7F, 0x17)), // amber
            Models.LogLevel.Information => new SolidColorBrush(Color.FromRgb(0x21, 0x21, 0x21)), // dark
            Models.LogLevel.Verbose => new SolidColorBrush(Color.FromRgb(0x75, 0x75, 0x75)),  // gray
            _ => new SolidColorBrush(Color.FromRgb(0x21, 0x21, 0x21))
        };
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

public class BuildStateToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is Models.BuildState state && parameter is string target)
        {
            return target switch
            {
                "Running" => state == Models.BuildState.Running || state == Models.BuildState.Cancelling
                    ? Visibility.Visible : Visibility.Collapsed,
                "Idle" => state == Models.BuildState.Idle ? Visibility.Visible : Visibility.Collapsed,
                _ => Visibility.Collapsed
            };
        }
        return Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}
