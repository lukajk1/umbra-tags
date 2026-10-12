param(
    # Defaults to the version in pubspec.yaml.
    [string]$Version,
    [switch]$Prerelease,
    # Reuse an existing Full installer folder instead of building one.
    [string]$InstallerDirectory,
    # Minutes to wait for the CI release workflow to publish the app installer.
    [int]$WaitMinutes = 30
)
# Publishes a GitHub release for this repository:
#   1. checks the working tree is clean, pushed, and matches pubspec.yaml;
#   2. builds the Full installer (app + offline ML runtime) and zips the setup
#      .exe with its .bin slice(s) so they download together;
#   3. tags v<version> and pushes it, which makes CI test, build and publish
#      the small App installer;
#   4. waits for that release, then attaches the Full zip and its checksum,
#      sets the notes from tool/release-notes/v<version>.md, and marks it as a
#      pre-release when asked.
# Requires: gh (logged in), Inno Setup 6, the sibling umbra-tags-ml checkout
# with its .venv and models.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $pubspec = [regex]::Match((Get-Content -LiteralPath pubspec.yaml -Raw), '(?m)^version:\s*(\d+\.\d+\.\d+)').Groups[1].Value
    if (-not $Version) { $Version = $pubspec }
    if ($Version -ne $pubspec) { throw "Version $Version does not match pubspec.yaml ($pubspec)." }
    $tag = "v$Version"
    $repo = (gh repo view --json nameWithOwner -q .nameWithOwner)
    if ($LASTEXITCODE -ne 0) { throw 'gh could not read the repository. Run gh auth login.' }

    if (git status --porcelain) { throw 'The working tree has uncommitted changes. Commit or stash them first.' }
    git fetch --quiet origin
    if ((git rev-parse HEAD) -ne (git rev-parse '@{u}')) { throw 'HEAD is not pushed to its upstream. Push first.' }

    # 2. Full installer, zipped with its slices.
    if (-not $InstallerDirectory) {
        & (Join-Path $PSScriptRoot 'build_installer.ps1') -Mode Full
        if ($LASTEXITCODE) { throw 'Full installer build failed.' }
        $InstallerDirectory = Get-ChildItem -LiteralPath (Join-Path $root 'dist') -Directory -Filter 'installer-Full-*' |
            Sort-Object LastWriteTime | Select-Object -Last 1 -ExpandProperty FullName
    }
    $parts = @(Get-ChildItem -LiteralPath $InstallerDirectory -File | Where-Object { $_.Extension -in '.exe', '.bin' })
    if (-not ($parts | Where-Object Extension -eq '.exe')) { throw "No setup .exe in $InstallerDirectory." }
    $out = Join-Path $root "dist/release-$tag"
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    $zip = Join-Path $out "UmbraTags-Full-Setup-$Version.zip"
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip }
    # The .bin slices are already LZMA-compressed; store them as they are.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::Open($zip, 'Create')
    try {
        foreach ($part in $parts) {
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $part.FullName, $part.Name, 'NoCompression') | Out-Null
        }
    } finally { $archive.Dispose() }
    $limit = 2GB
    if ((Get-Item -LiteralPath $zip).Length -ge $limit) {
        throw 'The Full zip is over GitHub''s 2 GB asset limit. Lower DiskSliceSize in installer.iss and upload the .exe and .bin files separately.'
    }
    $sums = Join-Path $out 'SHA256SUMS-full.txt'
    "$((Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLower())  $(Split-Path -Leaf $zip)" |
        Set-Content -LiteralPath $sums -Encoding ascii
    Write-Output "Full installer: $zip ($([math]::Round((Get-Item $zip).Length / 1MB)) MB)"

    # 3. Tag and push; CI builds and publishes the App installer.
    if (-not (git tag --list $tag)) { git tag -a $tag -m "Umbra Tags $Version" }
    git push origin $tag
    if ($LASTEXITCODE) { throw "Could not push $tag." }

    # 4. Wait for the release CI creates, then attach the Full installer.
    $deadline = (Get-Date).AddMinutes($WaitMinutes)
    do {
        gh release view $tag --repo $repo --json tagName 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { break }
        if ((Get-Date) -gt $deadline) { throw "CI did not publish $tag within $WaitMinutes minutes. Check: gh run list --workflow release.yml" }
        Start-Sleep -Seconds 30
    } while ($true)
    $run = gh run list --repo $repo --workflow release.yml --branch $tag --limit 1 --json databaseId -q '.[0].databaseId'
    if ($run) { gh run watch $run --repo $repo --exit-status | Out-Null }
    if ($LASTEXITCODE) { throw "The release workflow for $tag failed. See: gh run view $run --repo $repo --log-failed" }

    gh release upload $tag $zip $sums --repo $repo --clobber
    if ($LASTEXITCODE) { throw 'Uploading the Full installer failed.' }
    $edit = @('release', 'edit', $tag, '--repo', $repo, '--title', "Umbra Tags $Version")
    $notes = Join-Path $PSScriptRoot "release-notes/$tag.md"
    if (Test-Path -LiteralPath $notes) { $edit += @('--notes-file', $notes) }
    if ($Prerelease) { $edit += '--prerelease' }
    gh @edit
    if ($LASTEXITCODE) { throw 'Editing the release failed.' }
    gh release view $tag --repo $repo --json url,isPrerelease,assets -q '"\(.url)  prerelease=\(.isPrerelease)\n" + ([.assets[] | "  \(.name)  \(.size / 1048576 | floor) MB"] | join("\n"))'
} finally { Pop-Location }
