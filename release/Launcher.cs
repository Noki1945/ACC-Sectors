using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("ACC Sectors")]
[assembly: AssemblyDescription("Compact timing and track-relative overlay for Assetto Corsa Competizione")]
[assembly: AssemblyProduct("ACC Sectors")]
[assembly: AssemblyVersion("0.2.0.0")]
[assembly: AssemblyFileVersion("0.2.0.0")]

internal static class Launcher {
    const string Version = "0.2.0";
    static readonly string[] Payload = { "Overlay.ps1", "Telemetry.cs", "Broadcast.cs", "BroadcastConfig.ps1", "RegressionTests.ps1", "Preferences.ps1", "DeltaGraph.cs", "DeltaGraph.ps1" };

    [STAThread]
    static int Main(string[] args) {
        bool selfTest = false;
        string data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ACC Sectors", "Data");
        try {
            string switches = "";
            foreach (string arg in args) {
                switch (arg.ToLowerInvariant()) {
                    case "--demo": case "-demo": switches += " -Demo"; break;
                    case "--self-test": case "-selftest": switches += " -SelfTest"; selfTest = true; break;
                    case "--preview": case "-preview": switches += " -Preview"; break;
                    default: throw new ArgumentException("Unknown option: " + arg + "\nSupported: --demo, --self-test, --preview");
                }
            }
            Directory.CreateDirectory(data);
            Assembly assembly = Assembly.GetExecutingAssembly();
            byte[][] files = new byte[Payload.Length][];
            using (MemoryStream combined = new MemoryStream()) {
                for (int i = 0; i < Payload.Length; i++) {
                    using (Stream input = assembly.GetManifestResourceStream("AccSectors." + Payload[i])) {
                        if (input == null) throw new IOException("Missing bundled file: " + Payload[i]);
                        using (MemoryStream buffer = new MemoryStream()) { input.CopyTo(buffer); files[i] = buffer.ToArray(); }
                    }
                    combined.Write(files[i], 0, files[i].Length);
                }
                string fingerprint;
                using (SHA256 hash = SHA256.Create()) { fingerprint = BitConverter.ToString(hash.ComputeHash(combined.ToArray())).Replace("-", "").Substring(0, 16); }
                string runtime = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ACC Sectors", "Runtime", Version + "-" + fingerprint);
                Directory.CreateDirectory(runtime);
                for (int i = 0; i < Payload.Length; i++) File.WriteAllBytes(Path.Combine(runtime, Payload[i]), files[i]);

                string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
                if (!File.Exists(powershell)) throw new FileNotFoundException("Windows PowerShell 5.1 was not found.", powershell);
                ProcessStartInfo start = new ProcessStartInfo {
                    FileName = powershell,
                    Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -File " + Quote(Path.Combine(runtime, "Overlay.ps1")) + " -DataDirectory " + Quote(data) + switches,
                    WorkingDirectory = runtime,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };
                StringBuilder log = new StringBuilder();
                using (Process child = new Process { StartInfo = start }) {
                    child.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e) { if (e.Data != null) lock(log) log.AppendLine(e.Data); };
                    child.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e) { if (e.Data != null) lock(log) log.AppendLine(e.Data); };
                    child.Start(); child.BeginOutputReadLine(); child.BeginErrorReadLine(); child.WaitForExit();
                    File.WriteAllText(Path.Combine(data, "launch.log"), "ACC Sectors " + Version + "\r\nExit code: " + child.ExitCode + "\r\n" + log, new UTF8Encoding(false));
                    if (child.ExitCode != 0 && !selfTest) ShowError("Не удалось запустить оверлей.\n\n" + Shorten(log.ToString()) + "\n\nЖурнал: " + Path.Combine(data, "launch.log"));
                    return child.ExitCode;
                }
            }
        } catch (Exception error) {
            try { Directory.CreateDirectory(data); File.WriteAllText(Path.Combine(data, "launch.log"), error.ToString(), new UTF8Encoding(false)); } catch { }
            if (!selfTest) ShowError(error.Message);
            return 1;
        }
    }
    // Windows argument quoting, passed directly to CreateProcess, without a shell.
    static string Quote(string value) {
        StringBuilder result = new StringBuilder("\""); int slashes = 0;
        foreach(char c in value) {
            if(c == '\\') { slashes++; continue; }
            if(c == '"') { result.Append('\\', slashes * 2 + 1); result.Append(c); slashes = 0; continue; }
            result.Append('\\', slashes); slashes = 0; result.Append(c);
        }
        result.Append('\\', slashes * 2); result.Append('"'); return result.ToString();
    }
    static string Shorten(string value) { return value.Length > 1600 ? value.Substring(0, 1600) : value; }
    static void ShowError(string message) { MessageBox.Show(message, "ACC Sectors", MessageBoxButtons.OK, MessageBoxIcon.Error); }
}
