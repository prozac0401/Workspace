# Workspace development guidance

Read the relevant original specification and `docs/policies/tools.md` before changing a tool. Policy source is Markdown under `docs/`; the generated site is not the editing source. Keep requirements, architecture decisions, user guidance and verification records consistent.

## Highest implementation priority: confirmed requirements and minimum necessary work

- At every implementation stage, implement only what a confirmed requirement or a demonstrated defect needs. Do not add speculative features, abstractions, dependencies, background behavior, or support matrices for hypothetical future needs.
- Choose the smallest implementation that satisfies the requirement and preserves user data. Reuse existing behavior where its contract still applies; do not hide changed assumptions behind reuse.
- Run only checks needed for the changed behavior, a demonstrated failure, or a material data/installation risk. Preserve existing evidence and required relevant checks. Do not repeat completed manual tests or broaden to full GUI, installer, performance, or whole-suite runs without a concrete reason.
- For a stage, briefly state the requirement, intended change, and sufficient completion evidence in the existing work record. Stop expanding verification when that evidence is obtained unless a new failure or unresolved concern justifies more work. Do not create an extra approval or reporting workflow for routine choices.

This user-confirmed principle applies to all tools and to future DownloadVersionManager work. It does not turn missing or failed evidence into a pass.

For FolderState:

- Preserve folder names and business files. State operations must not enumerate descendants or read business file contents.
- Keep state and Explorer presentation separate. Preserve unknown metadata, user customizations and externally modified files.
- Changes to persistence require tests for interrupted writes, rollback, concurrent actions and reset compatibility.
- Maintain ordinary-user execution, HKCU installation and a self-contained Windows MSI.
- Run `dotnet run --project tests/FolderState.Tests -c Release` for engine changes. Run the WPF smoke renderer for UI changes. Use `scripts/build.ps1` for complete release builds.
- Use `scripts/verify-msi.ps1` for package checks. Run `scripts/test-installer.ps1` only when its preflight confirms there is no existing FolderState installation; it installs into a dedicated directory under `artifacts` and preserves business-folder fixtures.
- Record actual test results and limitations. Do not classify an unsigned or incompletely verified evaluation package as a commercially approved release.

For documentation:

- Follow `docs/policies/documentation.md` and use the forms under `docs/forms`.
- Mark organization-specific settings as proposals or unresolved decisions until they are actually decided.
- Run `python -m mkdocs build --strict` and validate generated local links before publication.
- Publish only content intended for public reading. Keep business records, credentials, user logs and local installer diagnostics out of the public site.

The `.tools`, `artifacts`, `bin`, `obj` and `site` directories are generated or local-only. Before deleting generated directories on Windows, verify the resolved target is inside this repository's intended output directory.
