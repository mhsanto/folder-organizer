using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace DesktopOrganizer
{
    public sealed class MoveRecord
    {
        public string Source { get; set; }
        public string Destination { get; set; }
        public long Length { get; set; }
        public long ModifiedTicks { get; set; }
        public bool Restored { get; set; }
    }

    public sealed class Journal
    {
        public int Version { get; set; }
        public string Desktop { get; set; }
        public string CreatedUtc { get; set; }
        public bool Undone { get; set; }
        public List<MoveRecord> Files { get; set; }
    }

    public sealed class Result
    {
        public string Folder { get; set; }
        public int Moved { get; set; }
        public int Skipped { get; set; }
        public string JournalPath { get; set; }
        public List<string> Messages { get; set; }
        public Dictionary<string, int> Categories { get; set; }
        public Result()
        {
            Messages = new List<string>();
            Categories = new Dictionary<string, int>();
        }
    }

    public sealed class Organizer
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct FindData
        {
            public uint Attributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME AccessTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME WriteTime;
            public uint SizeHigh;
            public uint SizeLow;
            public uint ReparseTag;
            public uint Reserved;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string Name;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)] public string AlternateName;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr FindFirstFile(string fileName, out FindData data);
        [DllImport("kernel32.dll")]
        private static extern bool FindClose(IntPtr handle);

        private static bool IsRedirected(string path)
        {
            if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) == 0) return false;
            FindData data;
            IntPtr handle = FindFirstFile(path, out data);
            if (handle == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error());
            try { return (data.ReparseTag & 0x20000000) != 0; }
            finally { FindClose(handle); }
        }

        private readonly string desktop;
        private readonly string history;
        private readonly string executable;
        private readonly JavaScriptSerializer json = new JavaScriptSerializer();
        private static readonly Dictionary<string, string> Types = BuildTypes();

        public Organizer(string desktopPath, string historyPath, string executablePath)
        {
            string fullPath = Path.GetFullPath(desktopPath);
            desktop = fullPath.Length > Path.GetPathRoot(fullPath).Length ?
                fullPath.TrimEnd(Path.DirectorySeparatorChar) : fullPath;
            history = Path.GetFullPath(historyPath);
            executable = Path.GetFullPath(executablePath);
            json.MaxJsonLength = Int32.MaxValue;
        }

        private static Dictionary<string, string> BuildTypes()
        {
            var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            Add(map, "Images", ".jpg .jpeg .png .gif .bmp .webp .svg .ico .tif .tiff .heic .heif .avif .raw .cr2 .nef .dng");
            Add(map, "Documents", ".doc .docx .odt .rtf .txt .md .pages .tex .epub .mobi .log");
            Add(map, "PDFs", ".pdf");
            Add(map, "Spreadsheets", ".xls .xlsx .xlsm .xlsb .csv .tsv .ods .numbers");
            Add(map, "Presentations", ".ppt .pptx .pptm .odp .key");
            Add(map, "Videos", ".mp4 .mkv .mov .avi .wmv .webm .m4v .mpeg .mpg .3gp .flv");
            Add(map, "Audio", ".mp3 .wav .flac .aac .m4a .ogg .opus .wma .aiff .mid .midi");
            Add(map, "Archives", ".zip .rar .7z .tar .gz .bz2 .xz .tgz .zst");
            Add(map, "Installers", ".exe .msi .msix .appx .msixbundle .appxbundle .iso .img");
            Add(map, "Code", ".js .jsx .ts .tsx .html .htm .css .scss .sass .less .json .xml .yaml .yml .toml .ini .cfg .conf .py .ipynb .go .rs .c .h .cpp .hpp .cs .java .php .rb .sql .sh .ps1 .bat .cmd .vue .svelte .swift .kt .lua .r");
            Add(map, "Design Files", ".psd .ai .eps .indd .fig .sketch .xd .afdesign .afphoto .blend .stl .obj .fbx .dwg .dxf");
            Add(map, "Fonts", ".ttf .otf .woff .woff2");
            return map;
        }

        private static void Add(Dictionary<string, string> map, string category, string extensions)
        {
            foreach (string extension in extensions.Split(' ')) map.Add(extension, category);
        }

        public static string Category(string path)
        {
            string category;
            return Types.TryGetValue(Path.GetExtension(path), out category) ? category : "Other Files";
        }

        private bool Eligible(string path)
        {
            var info = new FileInfo(path);
            string extension = info.Extension.ToLowerInvariant();
            string name = info.Name;
            if ((info.Attributes & (FileAttributes.Hidden | FileAttributes.System)) != 0) return false;
            if (IsRedirected(path)) return false;
            if (String.Equals(path, executable, StringComparison.OrdinalIgnoreCase)) return false;
            if (extension == ".lnk" || extension == ".url" || extension == ".website") return false;
            if (extension == ".tmp" || extension == ".temp" || extension == ".part" ||
                extension == ".partial" || extension == ".crdownload" || extension == ".download") return false;
            return !name.StartsWith("~$", StringComparison.OrdinalIgnoreCase);
        }

        private string Destination(string source)
        {
            string folder = Path.Combine(desktop, Category(source));
            if (File.Exists(folder)) throw new IOException("A file already uses the folder name " + Category(source));
            if (Directory.Exists(folder) && IsRedirected(folder))
                throw new IOException("The destination folder is a link: " + folder);
            Directory.CreateDirectory(folder);
            string candidate = Path.Combine(folder, Path.GetFileName(source));
            int suffix = 2;
            while (File.Exists(candidate) || Directory.Exists(candidate))
            {
                candidate = Path.Combine(folder, Path.GetFileNameWithoutExtension(source) +
                    " (" + suffix++ + ")" + Path.GetExtension(source));
            }
            return candidate;
        }

        private void Save(string path, Journal journal)
        {
            string temporary = path + ".tmp";
            byte[] bytes = new UTF8Encoding(false).GetBytes(json.Serialize(journal));
            using (var stream = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                stream.Write(bytes, 0, bytes.Length);
                stream.Flush(true);
            }
            if (File.Exists(path)) File.Replace(temporary, path, null);
            else File.Move(temporary, path);
        }

        public Result Organize(bool preview)
        {
            var result = new Result { Folder = desktop };
            if (!Directory.Exists(desktop)) throw new DirectoryNotFoundException(desktop);
            string[] files = Directory.GetFiles(desktop);
            var journal = new Journal {
                Version = 1, Desktop = desktop, CreatedUtc = DateTime.UtcNow.ToString("o"),
                Files = new List<MoveRecord>()
            };
            string journalPath = Path.Combine(history, DateTime.UtcNow.ToString("yyyyMMdd-HHmmss-fffffff") +
                "-" + Guid.NewGuid().ToString("N") + ".json");
            foreach (string file in files)
            {
                try
                {
                    if (!Eligible(file)) { result.Skipped++; continue; }
                    string category = Category(file);
                    if (!preview)
                    {
                        string destination = Destination(file);
                        var info = new FileInfo(file);
                        var record = new MoveRecord {
                            Source = file, Destination = destination, Length = info.Length,
                            ModifiedTicks = info.LastWriteTimeUtc.Ticks
                        };
                        Directory.CreateDirectory(history);
                        journal.Files.Add(record);
                        // Persist intent before moving so an interrupted run can still be undone.
                        Save(journalPath, journal);
                        try { File.Move(file, destination); }
                        catch
                        {
                            journal.Files.Remove(record);
                            Save(journalPath, journal);
                            throw;
                        }
                        result.JournalPath = journalPath;
                    }
                    result.Moved++;
                    if (!result.Categories.ContainsKey(category)) result.Categories.Add(category, 0);
                    result.Categories[category]++;
                }
                catch (Exception ex)
                {
                    result.Skipped++;
                    result.Messages.Add(Path.GetFileName(file) + ": " + ex.Message);
                }
            }
            return result;
        }

        public string LatestJournal()
        {
            if (!Directory.Exists(history)) return null;
            foreach (string path in Directory.GetFiles(history, "*.json").OrderByDescending(p => p))
            {
                Journal journal = json.Deserialize<Journal>(File.ReadAllText(path));
                if (!journal.Undone && journal.Files.Count > 0 &&
                    String.Equals(journal.Desktop, desktop, StringComparison.OrdinalIgnoreCase)) return path;
            }
            return null;
        }

        private bool IsValidRecord(MoveRecord record)
        {
            string source = Path.GetFullPath(record.Source);
            string destination = Path.GetFullPath(record.Destination);
            string parent = Path.GetDirectoryName(destination);
            return String.Equals(Path.GetDirectoryName(source), desktop, StringComparison.OrdinalIgnoreCase) &&
                String.Equals(Path.GetDirectoryName(parent), desktop, StringComparison.OrdinalIgnoreCase) &&
                String.Equals(Path.GetFileName(parent), Category(source), StringComparison.OrdinalIgnoreCase) &&
                !IsRedirected(parent);
        }

        public Result Undo(string journalPath)
        {
            var result = new Result { Folder = desktop };
            if (journalPath == null) { result.Messages.Add("There is no previous run to undo."); return result; }
            var journal = json.Deserialize<Journal>(File.ReadAllText(journalPath));
            if (journal.Version != 1 || !String.Equals(journal.Desktop, desktop, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("This undo record belongs to another folder or tool version.");
            foreach (MoveRecord record in journal.Files.AsEnumerable().Reverse())
            {
                if (record.Restored) continue;
                try
                {
                    if (File.Exists(record.Source) && !File.Exists(record.Destination))
                    {
                        record.Restored = true;
                        Save(journalPath, journal);
                        continue;
                    }
                    if (!IsValidRecord(record)) throw new IOException("The original folder path has changed.");
                    if (File.Exists(record.Source) || Directory.Exists(record.Source))
                        throw new IOException("The original name is in use; neither file was overwritten.");
                    if (!File.Exists(record.Destination))
                        throw new IOException("The sorted file is missing or has been renamed.");
                    var info = new FileInfo(record.Destination);
                    if (info.Length != record.Length || info.LastWriteTimeUtc.Ticks != record.ModifiedTicks)
                        throw new IOException("The sorted file has changed; restore it manually if needed.");
                    File.Move(record.Destination, record.Source);
                    result.Moved++;
                    record.Restored = true;
                    Save(journalPath, journal);
                }
                catch (Exception ex)
                {
                    result.Skipped++;
                    result.Messages.Add(Path.GetFileName(record.Source) + ": " + ex.Message);
                }
            }
            journal.Undone = journal.Files.All(f => f.Restored);
            Save(journalPath, journal);
            result.JournalPath = journalPath;
            return result;
        }
    }

    internal static class Program
    {
        private static string DownloadsFolder()
        {
            string value = Microsoft.Win32.Registry.GetValue(
                @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders",
                "{374DE290-123F-4565-9164-39C4925E467B}", null) as string;
            return String.IsNullOrEmpty(value) ? Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads") :
                Environment.ExpandEnvironmentVariables(value);
        }

        private static string Option(string[] args, string key, string fallback)
        {
            int index = Array.IndexOf(args, key);
            if (index < 0) return fallback;
            if (index + 1 >= args.Length || args[index + 1].StartsWith("--"))
                throw new ArgumentException("Missing value for " + key);
            return args[index + 1];
        }

        [STAThread]
        private static int Main(string[] args)
        {
            bool headless = args.Contains("--headless");
            string output = null;
            Application.EnableVisualStyles();
            try
            {
                output = Option(args, "--report", null);
                string defaultFolder = args.Contains("--downloads") ? DownloadsFolder() :
                    Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
                string desktop = Option(args, "--folder", Option(args, "--desktop", defaultFolder));
                string history = Option(args, "--history", Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DesktopOrganizer", "History"));
                bool undo = args.Contains("--undo");
                bool preview = args.Contains("--preview");
                using (var mutex = new Mutex(false, "Local\\DesktopOrganizer-" + Environment.UserName))
                {
                    bool acquired;
                    try { acquired = mutex.WaitOne(0); }
                    catch (AbandonedMutexException) { acquired = true; }
                    if (!acquired) throw new IOException("Folder Organizer is already running. Use its Choose folder button, or close its window first.");
                    try
                    {
                        var organizer = new Organizer(desktop, history, Application.ExecutablePath);
                        Result result = undo ? organizer.Undo(organizer.LatestJournal()) : organizer.Organize(preview);
                        if (output != null) WriteReport(output, result);
                        if (!headless) ShowResult(organizer, desktop, history, result, undo, preview);
                        return result.Messages.Count > 0 ? 2 : 0;
                    }
                    finally { mutex.ReleaseMutex(); }
                }
            }
            catch (Exception ex)
            {
                if (output != null)
                    WriteReport(output, new Result { Messages = new List<string> { ex.Message } });
                if (!headless) MessageBox.Show(ex.Message, "Folder Organizer", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }

        private static void WriteReport(string path, Result result)
        {
            File.WriteAllText(path, new JavaScriptSerializer().Serialize(result), new UTF8Encoding(false));
        }

        private static string Summary(Result result, bool undo, bool preview, string folder)
        {
            var text = new StringBuilder();
            text.AppendLine("Folder: " + folder);
            text.AppendLine();
            text.AppendLine(undo ? result.Moved + " file(s) restored to this folder." :
                preview ? result.Moved + " file(s) ready to organize." :
                result.Moved == 0 ? "No loose files were moved." : result.Moved + " file(s) organized.");
            text.AppendLine();
            foreach (var category in result.Categories.OrderBy(c => c.Key))
                text.AppendLine(category.Key + "  -  " + category.Value);
            if (!undo)
            {
                text.AppendLine();
                text.AppendLine("Existing folders, app shortcuts, hidden files and unfinished downloads stay in place.");
                text.AppendLine("Unknown file types go into Other Files. Existing files are never overwritten.");
            }
            else text.AppendLine("Category folders stay in place. You can delete them if they are empty.");
            if (result.Messages.Count > 0)
            {
                text.AppendLine();
                text.AppendLine("Some items need attention:");
                foreach (string message in result.Messages) text.AppendLine("- " + message);
            }
            return text.ToString();
        }

        private static string Heading(Result result, bool undo, bool preview)
        {
            return result.Messages.Count > 0 ? "Some files need attention" :
                undo ? "Files restored" : preview ? "Folder preview" :
                result.Moved > 0 ? result.Moved + (result.Moved == 1 ? " file organized" : " files organized") :
                "No loose files to organize";
        }

        private static void ShowResult(Organizer organizer, string desktop, string history,
            Result result, bool undo, bool preview)
        {
            using (var form = new Form())
            {
                form.Text = "Folder Organizer";
                form.Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
                form.ClientSize = new Size(680, 480);
                form.MinimumSize = new Size(500, 400);
                form.StartPosition = FormStartPosition.CenterScreen;
                form.Font = new Font("Segoe UI", 10);
                form.BackColor = Color.FromArgb(246, 248, 250);
                var heading = new Label {
                    Text = Heading(result, undo, preview),
                    Dock = DockStyle.Top, Height = 74, Padding = new Padding(22, 24, 10, 0),
                    Font = new Font("Segoe UI", 19, FontStyle.Bold), ForeColor = Color.FromArgb(28, 54, 48)
                };
                var details = new TextBox {
                    Multiline = true, ReadOnly = true, TabStop = false, BorderStyle = BorderStyle.None,
                    ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill,
                    BackColor = form.BackColor, Text = Summary(result, undo, preview, desktop)
                };
                var content = new Panel { Dock = DockStyle.Fill, Padding = new Padding(24, 10, 24, 12) };
                content.Controls.Add(details);
                var buttons = new FlowLayoutPanel {
                    Dock = DockStyle.Bottom, Height = 64, Padding = new Padding(16, 8, 16, 12),
                    FlowDirection = FlowDirection.RightToLeft
                };
                var close = new Button { Text = "Close", Width = 90, Height = 34 };
                close.Click += delegate { form.Close(); };
                var open = new Button { Text = "View this folder", Width = 140, Height = 34 };
                open.Click += delegate { System.Diagnostics.Process.Start("explorer.exe", "\"" + desktop + "\""); };
                var restore = new Button { Text = "Undo last sort", Width = 130, Height = 34 };
                restore.Enabled = organizer.LatestJournal() != null;
                restore.Click += delegate {
                    try
                    {
                        Result restored = organizer.Undo(organizer.LatestJournal());
                        details.Text = Summary(restored, true, false, desktop);
                        heading.Text = Heading(restored, true, false);
                        restore.Enabled = organizer.LatestJournal() != null;
                    }
                    catch (Exception ex) { MessageBox.Show(form, ex.Message, "Undo needs attention"); }
                };
                buttons.Controls.Add(close);
                buttons.Controls.Add(open);
                buttons.Controls.Add(restore);
                var choose = new Button {
                    Text = "Choose folder and organize...", Dock = DockStyle.Top, Height = 40,
                    BackColor = Color.FromArgb(32, 110, 85), ForeColor = Color.White,
                    FlatStyle = FlatStyle.Flat
                };
                choose.Click += delegate {
                    using (var dialog = new FolderBrowserDialog())
                    {
                        dialog.Description = "Choose a folder. Click OK to organize its loose files.";
                        dialog.SelectedPath = desktop;
                        dialog.ShowNewFolderButton = false;
                        if (dialog.ShowDialog(form) != DialogResult.OK) return;
                        try
                        {
                            form.UseWaitCursor = true;
                            desktop = dialog.SelectedPath;
                            organizer = new Organizer(desktop, history, Application.ExecutablePath);
                            Result sorted = organizer.Organize(false);
                            details.Text = Summary(sorted, false, false, desktop);
                            heading.Text = Heading(sorted, false, false);
                            restore.Enabled = organizer.LatestJournal() != null;
                        }
                        catch (Exception ex) { MessageBox.Show(form, ex.Message, "Folder Organizer"); }
                        finally { form.UseWaitCursor = false; }
                    }
                };
                var choosePanel = new Panel {
                    Dock = DockStyle.Bottom, Height = 66, Padding = new Padding(24, 8, 24, 8)
                };
                choosePanel.Controls.Add(choose);
                form.Controls.Add(content);
                form.Controls.Add(choosePanel);
                form.Controls.Add(buttons);
                form.Controls.Add(heading);
                form.AcceptButton = close;
                form.CancelButton = close;
                Application.Run(form);
            }
        }
    }
}
