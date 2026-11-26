using System;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

namespace WMemo.Wpf;

public partial class App : System.Windows.Application
{
    private const string MutexName = @"Local\WMemoSingleInstance";
    private const string PipeName = "WMemoSingleInstancePipe";
    private Mutex? singleInstanceMutex;
    private CancellationTokenSource? pipeCancellation;
    private bool ownsMutex;

    protected override void OnStartup(System.Windows.StartupEventArgs e)
    {
        singleInstanceMutex = new Mutex(initiallyOwned: true, MutexName, out var createdNew);
        ownsMutex = createdNew;
        if (!createdNew)
        {
            SignalExistingInstance();
            Shutdown();
            return;
        }

        NativeMethods.SetCurrentProcessExplicitAppUserModelID("WMemo.App");
        ShutdownMode = System.Windows.ShutdownMode.OnExplicitShutdown;
        var mainWindow = new MainWindow();
        MainWindow = mainWindow;
        StartPipeServer(mainWindow);
        mainWindow.Show();
        base.OnStartup(e);
    }

    protected override void OnExit(System.Windows.ExitEventArgs e)
    {
        pipeCancellation?.Cancel();
        if (ownsMutex)
        {
            singleInstanceMutex?.ReleaseMutex();
        }
        singleInstanceMutex?.Dispose();
        base.OnExit(e);
    }

    private void StartPipeServer(MainWindow mainWindow)
    {
        pipeCancellation = new CancellationTokenSource();
        _ = Task.Run(async () =>
        {
            while (!pipeCancellation.IsCancellationRequested)
            {
                try
                {
                    await using var server = new NamedPipeServerStream(PipeName, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
                    await server.WaitForConnectionAsync(pipeCancellation.Token);
                    using var reader = new StreamReader(server);
                    _ = await reader.ReadLineAsync(pipeCancellation.Token);
                    Dispatcher.Invoke(mainWindow.ShowFromTray);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch
                {
                }
            }
        }, pipeCancellation.Token);
    }

    private static void SignalExistingInstance()
    {
        try
        {
            using var client = new NamedPipeClientStream(".", PipeName, PipeDirection.Out);
            client.Connect(500);
            using var writer = new StreamWriter(client) { AutoFlush = true };
            writer.WriteLine("show");
        }
        catch
        {
        }
    }

    private static class NativeMethods
    {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        internal static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
    }
}
