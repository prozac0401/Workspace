# Third-party notices

The static calendar batch collector vendors `sax` 1.6.1 under the Blue Oak Model License 1.0.0. The complete license is in [tools/calendar/vendor/sax-LICENSE.md](tools/calendar/vendor/sax-LICENSE.md); upstream identity and integrity hashes are pinned in [manifest.json](tools/calendar/vendor/manifest.json). This parser runs in the collector and is not shipped in the browser assets. The calendar ZIP/OOXML writer is reused from the user-provided draft, which has no separate license file; public repository visibility is not a grant of a new license.

FolderState's self-contained Windows distribution includes the Microsoft .NET runtime and Windows Desktop runtime. Their licenses and notices are available in the upstream repositories:

- .NET runtime: https://github.com/dotnet/runtime/blob/main/LICENSE.TXT
- .NET runtime notices: https://github.com/dotnet/runtime/blob/main/THIRD-PARTY-NOTICES.TXT
- WPF: https://github.com/dotnet/wpf/blob/main/LICENSE.TXT
- Windows Forms / Windows Desktop components: https://github.com/dotnet/winforms/blob/main/LICENSE.TXT

Build-only dependencies (not installed into business folders): WiX Toolset 4.0.6, MkDocs 1.6.1, Material for MkDocs 9.7.7, Pillow for icon regeneration. Check each upstream license before changing versions or making a commercial release. WiX 4 is pinned; upgrading WiX requires a separate toolchain and licensing review.

The icons in assets/icons are generated from this repository's functional icon script. FolderState's own distribution license, publisher identity and commercial terms have not yet been selected by the repository owner. Public repository visibility alone does not grant a software license.
