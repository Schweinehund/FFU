# Roadmap: v2.0.0-alpha — C# WPF Application

## Milestone Goal

Create a native C# WPF application at `FFUBuilder.Desktop/` that calls the existing PowerShell modules unchanged via the PowerShell SDK. Both UIs coexist — the PowerShell UI stays intact. The C# app replaces all threading hacks with async/await + IProgress<T>, adds MVVM with CommunityToolkit, and provides compile-time XAML validation.

**User outcome:** Launch `FFUBuilder.exe`, see live preflight dashboard, configure settings, run a build with real-time progress, and cancel gracefully.

## Phases

### Phase 49: Project Foundation & PowerShell SDK — COMPLETE
**Goal:** Launchable app that loads all 15 PowerShell modules.
**Status:** Implemented and committed (c472e39)
**Key deliverables:** Solution, .csproj, admin manifest, DI container, PowerShellService, MainWindow shell with 4 tabs, 13 xUnit tests

### Phase 50: Dashboard & Preflight Integration — COMPLETE
**Goal:** Live preflight dashboard with real-time check results and repair buttons.
**Status:** Implemented and committed (a46ab87)
**Key deliverables:** PreflightService, PreflightCheck model with category/repair maps, DashboardViewModel, grouped DashboardView, StatusConverters, 13 new tests (26 total)

### Phase 51: Settings & Configuration — COMPLETE
**Goal:** Settings UI with two-way binding to config.json, compatible with PowerShell UI.
**Status:** Implemented
**Key deliverables:** BuildConfiguration model (~70 properties), SettingsViewModel with INotifyDataErrorInfo validation, SettingsView.xaml with 9 grouped sections, ConfigurationService with defaults/NullValueHandling, 19 new tests (45 total)

### Phase 52: Build Execution & Monitor — COMPLETE
**Goal:** Run BuildFFUVM.ps1 with real-time progress streaming and cancellation.
**Status:** Implemented
**Key deliverables:** BuildService with PowerShell streaming, MonitorViewModel with build state machine, MonitorView.xaml with progress bar and color-coded log viewer, LogEntry model, LogLevelToBrushConverter, auto-scroll log, 14 new tests (59 total)

### Phase 53: Polish, Testing & Versioning — COMPLETE
**Goal:** Production-ready error handling, About tab, comprehensive tests, version bump.
**Status:** Implemented
**Key deliverables:** AboutViewModel with version.json reading and module list, AboutView with GridView, ConfigRoundTripTests (4 integration tests), AboutViewModelTests (3 tests), 7 new tests (66 total)
**Success criteria met:**
1. Global exception handlers in App.xaml.cs (DispatcherUnhandledException + TaskScheduler.UnobservedTaskException)
2. About tab shows version info from version.json with module loaded/not-loaded status
3. 66 xUnit tests passing (well above 25+ target)
4. Config round-trip test passes (C# save -> load, PowerShell format -> C# load, full round-trip)
5. dotnet build: 0 warnings, 0 errors; dotnet test: 66/66 passed
