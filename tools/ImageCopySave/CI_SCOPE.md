# ImageCopySave v1.1 native menu candidate evaluation

Temporary source-only Windows CI trial within the user's continuing approval for testing followed by deletion. On 2026-09-25 the user removed the requirement to place Save inside the built-in New menu. The candidate registers independent native Windows 11 context commands for Directory\Background (Save) and supported single files (Copy). Full hiding without a supported image, no watcher, and first-menu placement remain requirements.

This trial builds an x64 C++ IExplorerCommand DLL, runs pure policy and direct COM contract tests, then publishes the existing self-contained helper and builds/unpacks an unsigned full MSIX evaluation package. Direct COM tests do not call Invoke, clipboard APIs, Explorer UI, package registration or installation. Package validation checks the declared command contexts, CLSIDs, native architecture, required assets and extracted file hashes. No certificate creation/import, trust changes, signing, developer-mode changes or Explorer restart occurs. The evaluation identity/publisher is provisional.

Policy/COM tests and package construction cannot pass G0. Actual Windows 11 first-menu visibility and state transitions, originating-tab context, command invocation, ordinary-user trusted installation/reinstallation/removal and M2 feedback/selection UI remain unverified or incomplete. No legacy-only or manual-registration fallback is implemented. The unsigned package is not a released installer.

Previous isolated engine/helper phases ended with 60, 68 and then 77 PASS. Their runs and artifacts are separate historical evidence. This native trial does not rerun the 77-case suite and must not be reported as a fresh engine or clipboard test. It never uses the user's clipboard.

After local evidence is retained, all temporary branch runs/logs and artifacts and the owned temporary branch will be deleted. Public Git objects and third-party copies cannot be guaranteed erased. No main merge, product release or site publication is authorized.
