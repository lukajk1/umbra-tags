namespace Calypso
{
    public class LibraryStub
    {
        public string Name    { get; set; } = string.Empty;
        public string Dirpath { get; set; } = string.Empty;

        public LibraryStub() { }
        public LibraryStub(string name, string dirpath) { Name = name; Dirpath = dirpath; }

        public static LibraryStub FromLibrary(Library lib) => new(lib.Name, lib.Dirpath);
    }
}
