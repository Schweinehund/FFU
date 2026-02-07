using System.Collections;
using System.ComponentModel;
using System.Text.RegularExpressions;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using FFUBuilder.App.Models;
using FFUBuilder.App.Services.Interfaces;
using Serilog;

namespace FFUBuilder.App.ViewModels;

public partial class SettingsViewModel : ObservableObject, INotifyDataErrorInfo
{
    private readonly IConfigurationService _configService;
    private readonly Dictionary<string, List<string>> _errors = new();
    private bool _isLoading;

    [ObservableProperty]
    private BuildConfiguration _configuration = null!;

    [ObservableProperty]
    private bool _isDirty;

    [ObservableProperty]
    private string _statusMessage = "Settings loaded with defaults";

    [ObservableProperty]
    private string? _configFilePath;

    [ObservableProperty]
    private string? _validationSummary;

    public SettingsViewModel(IConfigurationService configService)
    {
        _configService = configService;

        _isLoading = true;
        Configuration = BuildConfiguration.CreateDefaults();
        _isLoading = false;
    }

    partial void OnConfigurationChanged(BuildConfiguration value)
    {
        OnPropertyChanged(nameof(MemoryGB));
        OnPropertyChanged(nameof(DisksizeGB));
        ValidateAll();
    }

    #region GB Conversion Properties

    public double MemoryGB
    {
        get => Configuration.Memory / (1024.0 * 1024 * 1024);
        set
        {
            if (Math.Abs(MemoryGB - value) < 0.001) return;
            Configuration.Memory = (long)(value * 1024 * 1024 * 1024);
            OnPropertyChanged();
            ValidateProperty(nameof(MemoryGB));
            MarkDirty();
        }
    }

    public double DisksizeGB
    {
        get => Configuration.Disksize / (1024.0 * 1024 * 1024);
        set
        {
            if (Math.Abs(DisksizeGB - value) < 0.001) return;
            Configuration.Disksize = (long)(value * 1024 * 1024 * 1024);
            OnPropertyChanged();
            ValidateProperty(nameof(DisksizeGB));
            MarkDirty();
        }
    }

    #endregion

    #region Enum Option Lists

    public static int[] WindowsReleaseOptions => [10, 11, 2016, 2019, 2021, 2022, 2024, 2025];

    public static string[] WindowsSKUOptions =>
    [
        "Home", "Home N", "Home Single Language",
        "Education", "Education N",
        "Pro", "Pro N", "Pro Education", "Pro Education N",
        "Pro for Workstations", "Pro N for Workstations",
        "Enterprise", "Enterprise N",
        "Enterprise 2016 LTSB", "Enterprise N 2016 LTSB",
        "Enterprise LTSC", "Enterprise N LTSC",
        "IoT Enterprise LTSC", "IoT Enterprise N LTSC",
        "Standard", "Standard (Desktop Experience)",
        "Datacenter", "Datacenter (Desktop Experience)"
    ];

    public static string[] WindowsArchOptions => ["x86", "x64", "arm64"];

    public static string[] WindowsLangOptions =>
    [
        "ar-sa", "bg-bg", "cs-cz", "da-dk", "de-de", "el-gr", "en-gb", "en-us",
        "es-es", "es-mx", "et-ee", "fi-fi", "fr-ca", "fr-fr", "he-il", "hr-hr",
        "hu-hu", "it-it", "ja-jp", "ko-kr", "lt-lt", "lv-lv", "nb-no", "nl-nl",
        "pl-pl", "pt-br", "pt-pt", "ro-ro", "ru-ru", "sk-sk", "sl-si", "sr-latn-rs",
        "sv-se", "th-th", "tr-tr", "uk-ua", "zh-cn", "zh-tw"
    ];

    public static string[] MediaTypeOptions => ["consumer", "business"];

    public static string[] HypervisorTypeOptions => ["HyperV", "VMware", "Auto"];

    public static string[] MakeOptions =>
    [
        "", "Microsoft", "Dell", "HP", "Lenovo", "Acer",
        "Dynabook", "Panasonic", "Samsung", "Fujitsu", "ASUS", "MSI", "Getac"
    ];

    public static string[] BitsPriorityOptions => ["Foreground", "High", "Normal", "Low"];

    public static int[] LogicalSectorSizeOptions => [512, 4096];

    public static string[] VirtualDiskFormatOptions => ["VHD", "VHDX"];

    #endregion

    #region Commands

    [RelayCommand]
    private async Task LoadConfigAsync()
    {
        try
        {
            var path = ConfigFilePath;
            if (string.IsNullOrEmpty(path))
            {
                StatusMessage = "No config file path specified";
                return;
            }

            _isLoading = true;
            Configuration = await _configService.LoadAsync(path);
            _isLoading = false;

            IsDirty = false;
            ClearAllErrors();
            ValidateAll();
            StatusMessage = $"Configuration loaded from {path}";
            Log.Information("Settings loaded from {Path}", path);
        }
        catch (Exception ex)
        {
            _isLoading = false;
            StatusMessage = $"Failed to load: {ex.Message}";
            Log.Error(ex, "Failed to load configuration");
        }
    }

    [RelayCommand]
    private async Task SaveConfigAsync()
    {
        try
        {
            ValidateAll();
            if (HasErrors)
            {
                StatusMessage = "Cannot save — fix validation errors first";
                return;
            }

            var path = ConfigFilePath;
            if (string.IsNullOrEmpty(path))
            {
                StatusMessage = "No config file path specified";
                return;
            }

            await _configService.SaveAsync(path, Configuration);
            IsDirty = false;
            StatusMessage = $"Configuration saved to {path}";
            Log.Information("Settings saved to {Path}", path);
        }
        catch (Exception ex)
        {
            StatusMessage = $"Failed to save: {ex.Message}";
            Log.Error(ex, "Failed to save configuration");
        }
    }

    [RelayCommand]
    private void ResetToDefaults()
    {
        _isLoading = true;
        Configuration = BuildConfiguration.CreateDefaults();
        _isLoading = false;

        IsDirty = true;
        ClearAllErrors();
        ValidateAll();
        StatusMessage = "Reset to default settings";
        Log.Information("Settings reset to defaults");
    }

    #endregion

    #region INotifyDataErrorInfo

    public bool HasErrors => _errors.Any(kv => kv.Value.Count > 0);

    public event EventHandler<DataErrorsChangedEventArgs>? ErrorsChanged;

    public IEnumerable GetErrors(string? propertyName)
    {
        if (string.IsNullOrEmpty(propertyName))
            return _errors.SelectMany(kv => kv.Value);

        return _errors.TryGetValue(propertyName, out var errors) ? errors : [];
    }

    public void ValidateProperty(string propertyName)
    {
        ClearErrors(propertyName);

        switch (propertyName)
        {
            case nameof(MemoryGB):
                if (Configuration.Memory < 2147483648L)
                    AddError(propertyName, "Memory must be at least 2 GB");
                else if (Configuration.Memory > 137438953472L)
                    AddError(propertyName, "Memory must be at most 128 GB");
                break;

            case nameof(DisksizeGB):
                if (Configuration.Disksize < 26843545600L)
                    AddError(propertyName, "Disk size must be at least 25 GB");
                else if (Configuration.Disksize > 2199023255552L)
                    AddError(propertyName, "Disk size must be at most 2 TB");
                break;

            case "Processors":
                if (Configuration.Processors < 1)
                    AddError(propertyName, "Processors must be at least 1");
                else if (Configuration.Processors > 64)
                    AddError(propertyName, "Processors must be at most 64");
                break;

            case "MaxUSBDrives":
                if (Configuration.MaxUSBDrives < 0)
                    AddError(propertyName, "Max USB drives must be at least 0");
                else if (Configuration.MaxUSBDrives > 100)
                    AddError(propertyName, "Max USB drives must be at most 100");
                break;

            case "VMShutdownTimeoutMinutes":
                if (Configuration.VMShutdownTimeoutMinutes < 5)
                    AddError(propertyName, "VM shutdown timeout must be at least 5 minutes");
                else if (Configuration.VMShutdownTimeoutMinutes > 120)
                    AddError(propertyName, "VM shutdown timeout must be at most 120 minutes");
                break;

            case "FFUFileLockWaitSeconds":
                if (Configuration.FFUFileLockWaitSeconds < 30)
                    AddError(propertyName, "FFU file lock wait must be at least 30 seconds");
                else if (Configuration.FFUFileLockWaitSeconds > 600)
                    AddError(propertyName, "FFU file lock wait must be at most 600 seconds");
                break;

            case "VMName":
                if (!string.IsNullOrEmpty(Configuration.VMName) &&
                    !Regex.IsMatch(Configuration.VMName, @"^[a-zA-Z0-9_\-]+$"))
                    AddError(propertyName, "VM name must contain only letters, numbers, underscores, and hyphens");
                break;
        }

        OnPropertyChanged(nameof(HasErrors));
        UpdateValidationSummary();
    }

    public void ValidateAll()
    {
        ValidateProperty(nameof(MemoryGB));
        ValidateProperty(nameof(DisksizeGB));
        ValidateProperty("Processors");
        ValidateProperty("MaxUSBDrives");
        ValidateProperty("VMShutdownTimeoutMinutes");
        ValidateProperty("FFUFileLockWaitSeconds");
        ValidateProperty("VMName");
    }

    private void AddError(string propertyName, string error)
    {
        if (!_errors.ContainsKey(propertyName))
            _errors[propertyName] = [];

        if (!_errors[propertyName].Contains(error))
        {
            _errors[propertyName].Add(error);
            ErrorsChanged?.Invoke(this, new DataErrorsChangedEventArgs(propertyName));
        }
    }

    private void ClearErrors(string propertyName)
    {
        if (_errors.Remove(propertyName))
        {
            ErrorsChanged?.Invoke(this, new DataErrorsChangedEventArgs(propertyName));
        }
    }

    private void ClearAllErrors()
    {
        var properties = _errors.Keys.ToList();
        _errors.Clear();
        foreach (var prop in properties)
        {
            ErrorsChanged?.Invoke(this, new DataErrorsChangedEventArgs(prop));
        }
    }

    private void UpdateValidationSummary()
    {
        var errorCount = _errors.Values.Sum(e => e.Count);
        ValidationSummary = errorCount > 0
            ? $"{errorCount} validation error(s)"
            : null;
    }

    #endregion

    private void MarkDirty()
    {
        if (!_isLoading)
            IsDirty = true;
    }
}
