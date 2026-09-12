# Third-party notices

FolderState's self-contained Windows distribution includes the Microsoft .NET runtime and Windows Desktop runtime. Their licenses and notices are available in the upstream repositories:

- .NET runtime: https://github.com/dotnet/runtime/blob/main/LICENSE.TXT
- .NET runtime notices: https://github.com/dotnet/runtime/blob/main/THIRD-PARTY-NOTICES.TXT
- WPF: https://github.com/dotnet/wpf/blob/main/LICENSE.TXT
- Windows Forms / Windows Desktop components: https://github.com/dotnet/winforms/blob/main/LICENSE.TXT

Build-only dependencies (not installed into business folders): WiX Toolset 4.0.6, MkDocs 1.6.1, Material for MkDocs 9.7.7, Pillow for icon regeneration. Check each upstream license before changing versions or making a commercial release. WiX 4 is pinned; upgrading WiX requires a separate toolchain and licensing review.

The icons in assets/icons are generated from this repository's functional icon script. FolderState's own distribution license, publisher identity and commercial terms have not yet been selected by the repository owner. Public repository visibility alone does not grant a software license.
