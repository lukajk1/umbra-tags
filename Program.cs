namespace Calypso
{
    internal static class Program
    {
        [STAThread]
        static void Main()
        {
            ApplicationConfiguration.Initialize();
            Application.Run(new AppContext());
        }
    }

    internal class AppContext : ApplicationContext
    {
        public AppContext()
        {
            var bootstrapper = new Bootstrapper(this);
            bootstrapper.Show();
        }

        public void TransitionTo(Form mainForm)
        {
            MainForm = mainForm;
        }
    }
}