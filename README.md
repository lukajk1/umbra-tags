# Calypso Image Manager

A Windows desktop image library manager built with WinForms (.NET 8).

## Requirements

- Windows x64
- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8)

## Clone

```bash
git clone https://github.com/lukajk1/calypso
```

## Build & Run

```bash
# Restore dependencies
dotnet restore

# Build
dotnet build

# Run
dotnet run
```

Or open `Calypso.sln` in Visual Studio 2022+ and press F5.

## Dependencies

All packages restore automatically via NuGet.

| Package | Version | License |
|---------|---------|---------|
| Newtonsoft.Json | 13.0.3 | MIT |
| Imazen.WebP | 11.0.0 | MIT |
| Imazen.WebP.NativeRuntime.win-x64 | 1.6.1 | MIT |

### Open Source Notices

**Imazen.WebP** — Copyright 2012–2026 Imazen LLC  
Licensed under the MIT License. https://github.com/imazen/libwebp-net

## Supported File Types

`.jpg` `.jpeg` `.png` `.bmp` `.gif` `.webp`
