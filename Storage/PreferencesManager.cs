using Newtonsoft.Json;
using System.Diagnostics;

namespace Calypso
{
    internal static class PreferencesManager
    {
        private static string filePath = string.Empty;
        public static AppPreferences Prefs { get; private set; } = new AppPreferences();

        public static void Init()
        {
            string appDataPath = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            filePath = Path.Combine(appDataPath, "Calypso", "preferences.json");
            Load();
        }

        public static void Save()
        {
            try
            {
                string json = JsonConvert.SerializeObject(Prefs, Formatting.Indented);
                File.WriteAllText(filePath, json);
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Failed to save preferences: {ex.Message}");
            }
        }

        private static void Load()
        {
            try
            {
                if (!File.Exists(filePath)) return;
                string json = File.ReadAllText(filePath);
                Prefs = JsonConvert.DeserializeObject<AppPreferences>(json) ?? new AppPreferences();
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Failed to load preferences: {ex.Message}");
            }
        }
    }
}
