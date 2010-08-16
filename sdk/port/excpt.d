module sdk.port.excpt;

public:

enum EXCEPTION_DISPOSITION
{
         ExceptionContinueExecution = 0,
         ExceptionContinueSearch = 1,
         ExceptionNestedException = 2,
         ExceptionCollidedUnwind = 3
}

