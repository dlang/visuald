module winmain;

import core.runtime;
import core.sys.windows.windows;

extern (Windows)
int WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
{
    int result;

    void exceptionHandler(Throwable e)
    {
        throw e;
    }

    try
    {
        Runtime.initialize(&exceptionHandler);

        result = myWinMain(hInstance, hPrevInstance, lpCmdLine, nCmdShow);

        Runtime.terminate(&exceptionHandler);
    }
    catch (Throwable o)		// catch any uncaught exceptions
    {
        MessageBoxA(null, cast(char *)o.toString(), "Error", MB_OK | MB_ICONEXCLAMATION);
        result = 0;		// failed
    }

    return result;
}

int myWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
{
    /* ... insert user code here ... */
    throw new Exception("not implemented");
    return 0;
}
