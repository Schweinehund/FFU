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

### Phase 51: Settings & Configuration
**Goal:** Settings UI with two-way binding to config.json, compatible with PowerShell UI.
**Plans:** 2 plans
Plans:
- [ ] 51-01-PLAN.md -- Expand BuildConfiguration model + SettingsViewModel with validation
- [ ] 51-02-PLAN.md -- SettingsView.xaml UI + xUnit tests

**Success criteria:**
1. All major config properties editable in UI
2. Save produces valid config.json readable by PowerShell UI
3. Load reads config.json saved by PowerShell UI
4. Validation errors shown inline
5. Reset to defaults works

### Phase 52: Build Execution & Monitor
**Goal:** Run BuildFFUVM.ps1 with real-time progress streaming and cancellation.
**Success criteria:**
1. Build button launches BuildFFUVM.ps1 and switches to Monitor tab
2. Progress bar updates in real-time from PowerShell progress stream
3. Log entries appear as build runs (verbose, warning, error color-coded)
4. Cancel button stops build gracefully
5. Build completes successfully and creates FFU file
6. Build button disabled when critical preflight checks fail

### Phase 53: Polish, Testing & Versioning
**Goal:** Production-ready error handling, About tab, comprehensive tests, version bump.
**Success criteria:**
1. All exceptions caught and logged (no unhandled crashes)
2. About tab shows correct version info
3. 25+ xUnit tests passing
4. Config round-trip test passes (C# <-> PowerShell compatibility)
5. dotnet build zero warnings, dotnet test all green
6. README documents how to build and run the C# app
