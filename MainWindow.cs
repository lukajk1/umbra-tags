
using Calypso.UI;
using System.Diagnostics;
using System.Windows.Forms;

namespace Calypso
{
    public enum Pane
    {
        TagSideTab,
        Gallery,
        Searchbar
    }
    public partial class MainWindow : Form
    {
        public static MainWindow i;
        public static Pane FocusedPane;
        public static bool initialized;

        const string ProgramName = "Umbra Tags";
        public MainWindow(bool deferInit = false)
        {
            CreateSingleton();

            InitializeComponent();
            ThemeManager.Apply(this);
            this.BackColor = Theme.Background;
            this.ForeColor = Theme.Foreground;
            ThemeManager.SetImmersiveDarkMode(this.Handle, Theme.IsDark);
            AddImportWizardMenuItem();
            AddThemeMenu();
            this.KeyPreview = true;
            this.FormClosed += MainWindow_FormClosed;
            this.MouseWheel += MainWindow_MouseWheel;
            this.Text = $"{ProgramName} {GlobalValues.Version} - ...";

            Activate();
            Focus();

            comboBoxResultsNum.SelectedIndex = 0;

            Gallery.Init(this);
            StatusBar.Init(this);
            ImageInfoPanel.Init(this);
            Searchbar.Init(this);
            TagEditManager.Init(this);
            LayoutManager.Init(this);
            ShortcutHandler.Init(this);

            if (!deferInit)
                PostInit();
        }

        /// <summary>
        /// Completes startup. When going through Bootstrapper, DB.InitBackground + DB.InitUI
        /// are called first, then this. When not using Bootstrapper, this calls DB.Init itself.
        /// </summary>
        public void PostInit(bool dbAlreadyInitialized = false)
        {
            if (!dbAlreadyInitialized)
                DB.Init(this);
            new TagTreePanel(this);
            LibraryUIManager.Init(this);
            initialized = true;
            if (dbAlreadyInitialized)
                DB.InitUIFinal();
        }

        private void AddImportWizardMenuItem()
        {
            var item = new ToolStripMenuItem("Import from Downloads...");
            item.Click += (_, _) => ImportWizardModal.RunFromDownloads();
            fileToolStripMenuItem.DropDownItems.Insert(0, item);
            fileToolStripMenuItem.DropDownItems.Insert(1, new ToolStripSeparator());

            var detectItem = new ToolStripMenuItem("Run Photo Detection...");
            detectItem.Click += (_, _) => PhotoDetectionModal.Run();
            fileToolStripMenuItem.DropDownItems.Insert(2, detectItem);
            fileToolStripMenuItem.DropDownItems.Insert(3, new ToolStripSeparator());

            Calypso.UI.ThemeManager.Apply(menuStrip1);
        }

        private void AddThemeMenu()
        {
            var themeMenu = new ToolStripMenuItem("Theme");

            var darkItem   = new ToolStripMenuItem("Dark")   { Name = "themeItemDark" };
            var lightItem  = new ToolStripMenuItem("Light")  { Name = "themeItemLight" };
            var systemItem = new ToolStripMenuItem("System") { Name = "themeItemSystem" };

            darkItem.Click   += (_, _) => SetTheme(ThemeMode.Dark);
            lightItem.Click  += (_, _) => SetTheme(ThemeMode.Light);
            systemItem.Click += (_, _) => SetTheme(ThemeMode.System);

            themeMenu.DropDownItems.AddRange(new ToolStripItem[] { darkItem, lightItem, systemItem });
            viewToolStripMenuItem.DropDownItems.Add(new ToolStripSeparator());
            viewToolStripMenuItem.DropDownItems.Add(themeMenu);

            UpdateThemeCheckmarks();
            Calypso.UI.ThemeManager.Apply(menuStrip1);
        }

        private void SetTheme(ThemeMode mode)
        {
            ThemeManager.SetTheme(mode);
            UpdateThemeCheckmarks();
        }

        private void UpdateThemeCheckmarks()
        {
            foreach (ToolStripItem item in viewToolStripMenuItem.DropDownItems)
            {
                if (item is not ToolStripMenuItem sub || sub.Text != "Theme") continue;
                foreach (ToolStripItem child in sub.DropDownItems)
                {
                    if (child is ToolStripMenuItem mi)
                        mi.Checked = mi.Name switch
                        {
                            "themeItemDark"   => ThemeManager.CurrentMode == ThemeMode.Dark,
                            "themeItemLight"  => ThemeManager.CurrentMode == ThemeMode.Light,
                            "themeItemSystem" => ThemeManager.CurrentMode == ThemeMode.System,
                            _                 => false
                        };
                }
            }
        }

        public void UpdateTitle(string libraryName)
        {
            this.Text = $"{ProgramName} {GlobalValues.Version} - {libraryName}";
        }
        private void CreateSingleton()
        {
            if (i == null)
                i = this;
            else
                Util.ShowErrorDialog("There are multiple main window instances.");
        }
        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if (ShortcutHandler.HandleGlobal(keyData)) return true;
            if (FocusedPane == Pane.Searchbar) return base.ProcessCmdKey(ref msg, keyData);
            if (ShortcutHandler.HandleContextual(keyData)) return true;
            return base.ProcessCmdKey(ref msg, keyData);
        }
        private void MainWindow_MouseWheel(object sender, MouseEventArgs e)
        {
            Gallery.ZoomFromWheel(e);
        }

        private static readonly Size DefaultWindowedSize = new Size(1100, 720);

        public void LoadSession(Session session)
        {
            var screen = Screen.FromControl(this).WorkingArea;
            bool sizeValid = session.WindowWidth >= MinimumSize.Width
                          && session.WindowHeight >= MinimumSize.Height
                          && session.WindowWidth < screen.Width
                          && session.WindowHeight < screen.Height;

            var size = sizeValid ? new Size(session.WindowWidth, session.WindowHeight) : DefaultWindowedSize;
            this.Size = size;
            this.checkBoxRandomize.Checked = session.RandomiseChecked;
            this.WindowState = session.WindowState;
            Gallery.Zoom = session.ZoomModifier;
            if (session.LastActiveLibrary != null)
                UpdateTitle(session.LastActiveLibrary.Name);
        }

        private void MainWindow_FormClosed(object sender, FormClosedEventArgs e)
        {
            DB.OnClose(CaptureCurrentSession());
        }

        public void ApplyPreferences(AppPreferences prefs)
        {
            hideFilenamesToolStripMenuItem.Checked = !prefs.ShowFilenames;
            Gallery.RefreshTileLabels();
        }

        public Session CaptureCurrentSession()
        {
            return new Session(
                windowHeight: this.Height,
                windowWidth: this.Width,
                randomiseChecked: this.checkBoxRandomize.Checked,
                windowState: this.WindowState,
                lastActiveLibrary: DB.appdata.ActiveLibrary,
                zoomModifier: Gallery.Zoom,
                lastSearch: searchBox.Text
            );
        }

        private void exitToolStripMenuItem_Click(object sender, EventArgs e) => Close();

        private void aboutToolStripMenuItem_Click(object sender, EventArgs e)
        {
            string message = $"Calypso Image Manager {GlobalValues.Version}\nSupported file types: .jpg, .jpeg, .jfif, .png, .bmp, .gif, .webp\nCreated by Luka Kawashima\n\nOpen Source Notices:\nImazen.WebP (MIT) — Copyright 2012–2026 Imazen LLC\nhttps://github.com/imazen/libwebp-net\nNewtonsoft.Json (MIT) — Copyright 2007 James Newton-King\nhttps://github.com/JamesNK/Newtonsoft.Json";
            MessageBox.Show(message, "About Calypso", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private void textBox1_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
            {
                e.SuppressKeyPress = true;
                e.Handled = true;
                if (!File.Exists(searchBox.Text))
                    Searchbar.Search(searchBox.Text);
            }
        }

        private void toolStripMenuItem5_Click(object sender, EventArgs e) => LayoutManager.SetLayout(LayoutManager.DefaultLayout);
        private void toolStripMenuItem3_Click(object sender, EventArgs e) => LayoutManager.SetLayout(LayoutManager.LargeWindow);
        private void toolStripMenuItem9_Click(object sender, EventArgs e) => Commands.AddFilesViaDialog();
        private void toolStripMenuItem1_Click_1(object sender, EventArgs e) => DB.OpenCurrentLibrarySourceFolder();
        private void syncLibraryToolStripMenuItem_Click(object sender, EventArgs e) => DB.RefreshLibrary();
        private void checkBoxRandomize_CheckedChanged(object sender, EventArgs e) => Searchbar.RepeatLastSearch();
        private void newGalleryToolStripMenuItem_Click(object sender, EventArgs e) => DB.AddNewLibrary();
        private void removeTagToolStripMenuItem_Click(object sender, EventArgs e) => TagTreePanel.i.RenameTag(sender);
        private void deleteToolStripMenuItem_Click(object sender, EventArgs e) => TagTreePanel.i.DeleteTag(sender);
        private void addChildTagToolStripMenuItem_Click(object sender, EventArgs e) => TagTreePanel.i.AddChildTag(sender);

        private void addNewTagToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (Util.TextPrompt("Set tag name: ", out string newTag))
                DB.ActiveLibrary.AddTagToTree(new TagNode(newTag));
        }

        private void addTagButton_Click(object sender, EventArgs e)
        {
            if (Util.TextPrompt("Set tag name: ", out string newTag))
                DB.ActiveLibrary.AddTagToTree(new TagNode(newTag));
        }

        private void searchButton_Click(object sender, EventArgs e)
        {
            Searchbar.Search(searchBox.Text);
        }

        private void hideFilenamesToolStripMenuItem_Click(object sender, EventArgs e)
        {
            PreferencesManager.Prefs.ShowFilenames = !PreferencesManager.Prefs.ShowFilenames;
            hideFilenamesToolStripMenuItem.Checked = !PreferencesManager.Prefs.ShowFilenames;
            Gallery.RefreshTileLabels();
        }

        private void preferencesToolStripTextBox_Click(object sender, EventArgs e)
        {
            new Preferences().ShowDialog();
        }

        private void exportTagsToCSV_Click(object sender, EventArgs e)
        {
            var lib = DB.ActiveLibrary;
            if (lib == null) { Util.ShowErrorDialog("No active library."); return; }

            using var dlg = new FolderBrowserDialog
            {
                Description = "Choose export folder",
                UseDescriptionForTitle = true
            };
            if (dlg.ShowDialog() != DialogResult.OK) return;

            string path = Path.Combine(dlg.SelectedPath,
                $"{lib.Name}_tags_{DateTime.Now:yyyyMMdd_HHmmss}.csv");

            try
            {
                var sb = new System.Text.StringBuilder();
                sb.AppendLine("filepath,tags");

                foreach (var img in lib.filenameDict.Values)
                {
                    var tags = lib.tagDict
                        .Where(kv => kv.Value.Contains(img))
                        .Select(kv => kv.Key);

                    string tagList = string.Join("|", tags);
                    sb.AppendLine($"\"{img.Filepath}\",\"{tagList}\"");
                }

                File.WriteAllText(path, sb.ToString(), System.Text.Encoding.UTF8);
                MessageBox.Show($"Exported to:\n{path}", "Export complete",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                Util.ShowErrorDialog($"Export failed: {ex.Message}");
            }
        }
    }
}
