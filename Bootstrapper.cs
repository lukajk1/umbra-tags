using System.Threading.Tasks;
using System.Windows.Forms;

namespace Calypso
{
    internal partial class Bootstrapper : Form
    {
        private readonly AppContext _ctx;

        public Bootstrapper(AppContext ctx)
        {
            _ctx = ctx;
            InitializeComponent();
            StartPosition = FormStartPosition.CenterScreen;
            this.Shown   += Bootstrapper_Shown;
        }

        private async void Bootstrapper_Shown(object? sender, EventArgs e)
        {
            var mainWindow = new MainWindow(deferInit: true);

            bool ok = await Task.Run(() => DB.InitBackground());

            if (ok)
            {
                DB.InitUI(mainWindow);
                mainWindow.PostInit(dbAlreadyInitialized: true);
            }

            _ctx.TransitionTo(mainWindow);
            mainWindow.Show();
            this.Close();
        }
    }
}
