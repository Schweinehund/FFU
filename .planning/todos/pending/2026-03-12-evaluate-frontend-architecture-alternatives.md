---
created: 2026-03-12T03:27:53.992Z
title: Evaluate frontend architecture alternatives
area: general
files:
  - FFUDevelopment/BuildFFUVM_UI.ps1
  - FFUDevelopment/BuildFFUVM_UI.xaml
  - FFUDevelopment/FFUUI.Core/
---

## Problem

The current UI uses WPF hosted via PowerShell (BuildFFUVM_UI.ps1 + 90KB XAML). While functional, this approach has known pain points: synchronous Loaded event blocks rendering (white screen on startup), 200+ FindName() lookups, thread-safe messaging complexity via ConcurrentQueue, and WPF's age as a framework. Need to evaluate whether this is the most efficient, reliable, scalable, and overall best framework for the project.

## Solution

- Evaluate current WPF/PowerShell approach against alternatives (WinUI 3, MAUI, Electron, web-based/Blazor, etc.)
- Consider constraints: PowerShell backend, Windows-only deployment, admin elevation requirements, Hyper-V/VMware integration
- Assess migration cost vs benefit for each alternative
- Evaluate maintainability, community support, and long-term viability
- Produce recommendation with rationale
