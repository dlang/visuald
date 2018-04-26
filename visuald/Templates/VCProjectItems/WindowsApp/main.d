import std.stdio;
import core.sys.windows.windows;

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

