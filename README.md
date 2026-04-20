# Calypso Image Manager

A Windows desktop image library manager built with WinForms (.NET 8).

## Requirements

- Windows x64
- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8)

## Build from Source

```bash
git clone https://github.com/lukajk1/calypso
cd calypso
dotnet restore
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

The executable will be at `bin/Release/net8.0-windows/publish/win-x64/Calypso.exe`.

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

**Newtonsoft.Json** — Copyright 2007 James Newton-King  
Licensed under the MIT License. https://github.com/JamesNK/Newtonsoft.Json

## Supported File Types

`.jpg` `.jpeg` `.png` `.bmp` `.gif` `.webp`
