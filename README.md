# Folder Organizer

A small Windows tool that sorts loose files into folders by type, with undo.
Use it on Desktop, Downloads, another folder, or the top level of a drive.

## Download

[**Download the latest release**](https://github.com/mhsanto/folder-organizer/releases/latest).

- **Setup.exe — recommended:** installs for your Windows account without admin access.
  Find **Organize Desktop** and **Organize Downloads** under **Folder Organizer** in Start.
- **Portable.exe:** a single file. Double-clicking it immediately organizes your Desktop.

Installation itself does not move any files. The app is unsigned, like AI Usage Monitor.
Release downloads include `SHA256SUMS.txt` to verify their contents.

## Use it

1. Open **Organize Desktop** or **Organize Downloads** from Start.
2. The tool sorts that folder immediately and shows the result and its full path.
3. For somewhere else, click **Choose folder and organize…**, select the folder and click **OK**.

**View this folder** only opens File Explorer. It does not start another sort.
**Undo last sort** restores the latest run for the folder currently shown.
Start also has separate undo shortcuts for Desktop and Downloads.

Choosing `D:\` sorts files directly in `D:\`. Existing folders and the files inside them
stay in place. The tool does **not** scan all subfolders across a drive.

## What goes where

The tool creates these folders only when needed: Images, Documents, PDFs, Spreadsheets,
Presentations, Videos, Audio, Archives, Installers, Code, Design Files, Fonts, and Other Files.
It groups by filename extension; it does not inspect document contents.

For example, `photo.jpg` goes into Images, `invoice.pdf` into PDFs, and `budget.xlsx`
into Spreadsheets. Unknown extensions and extensionless files go into Other Files.

## File safety and undo

- Existing category folders are reused. Other existing folders are left alone.
- Existing files are never overwritten. A duplicate receives a name such as `report (2).pdf`.
- App/website shortcuts, hidden/system files, symbolic links, temporary Office files,
  temporary files and unfinished downloads are skipped.
- Locked or inaccessible files are reported while other eligible files can still be sorted.
- Undo history is separate for each folder. Empty category folders remain after undo.
- Undo skips files edited since sorting, missing files, and original names now in use.
  These items can be restored manually without overwriting newer work.

History is stored in `%LOCALAPPDATA%\DesktopOrganizer\History`, compatible with the
original local Desktop Organizer tool. Keep this folder while you still need undo.
Uninstalling removes the program and Start shortcuts; it preserves history and your files.

Desktop and Downloads use Windows' configured locations, including redirected folders.
Moving files in OneDrive can also sync those changes to your other devices.
Cloud-only placeholders and cross-device sync have not been tested.

## Command line

```powershell
# Desktop (default)
& '.\Folder Organizer.exe'

# Downloads
& '.\Folder Organizer.exe' --downloads

# A specific folder or drive root
& '.\Folder Organizer.exe' --folder 'D:\My Files'

# Preview without moving files
& '.\Folder Organizer.exe' --folder 'D:\My Files' --preview

# Undo the most recent sort of that folder
& '.\Folder Organizer.exe' --folder 'D:\My Files' --undo
```

For automation, `--headless` suppresses windows, `--report <path>` writes a JSON result,
and `--history <folder>` uses a separate undo-history location. `--desktop <path>` remains
supported as a legacy alias for `--folder`.

## Build and test

Requires 64-bit Windows and .NET Framework 4. The app uses Windows Forms and has no npm,
Rust, WebView or third-party runtime dependencies. NSIS 3 is needed only to build the installer.

```powershell
./scripts/Build.ps1
./tests/Integration.ps1 -Executable "$pwd/dist/Folder Organizer.exe"
./scripts/Package.ps1
```

Every push and pull request builds the app, tests real file operations in temporary folders,
and creates an installer, portable executable and checksums as a GitHub Actions artifact.
Build output stays in the ignored `dist/` directory. Tests never use your real Desktop
or Downloads. A custom `-TestRoot` keeps their temporary files somewhere you choose.

Test coverage includes file categories, filenames, duplicate protection, excluded files,
locked files, repeated runs, undo conflicts and redirected destination folders.
