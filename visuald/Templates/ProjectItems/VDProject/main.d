module $safeprojectname$;

$if$ ($subsystem$ == Windows)import core.sys.windows.windows;

alias extern(C) int function(string[] args) MainFunc;
extern (C) int _d_run_main(int argc, char **argv, MainFunc mainFunc);

extern (Windows)
int WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
{
    return _d_run_main(0, null, &main); // arguments unused, retrieved via CommandLineToArgvW
}

extern(C) int main(string[] args)
{
    MessageBoxW(null, "Hello D World!"w.ptr, "D Windows Application"w.ptr, MB_OK);
    return 0;
}
$endif$ $if$ ($subsystem$ == Console) import std.stdio;

int main()
{
    writeln("Hello D World!\n");
    return 0;
}
$endif$ $if$ ($subsystem$ == DynamicLibrary) import core.sys.windows.windows;
import core.sys.windows.dll;

__gshared HINSTANCE g_hInst;

extern (Windows)
BOOL DllMain(HINSTANCE hInstance, ULONG ulReason, LPVOID pvReserved)
{
    switch (ulReason)
    {
        case DLL_PROCESS_ATTACH:
            g_hInst = hInstance;
            dll_process_attach(hInstance, true);
            break;

        case DLL_PROCESS_DETACH:
            dll_process_detach(hInstance, true);
            break;

        case DLL_THREAD_ATTACH:
            dll_thread_attach(true, true);
            break;

        case DLL_THREAD_DETACH:
            dll_thread_detach(true, true);
            break;

        default:
            break;
    }
    return true;
}
$endif$
