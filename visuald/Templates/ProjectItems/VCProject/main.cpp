#include "stdafx.h"

// D runtime initialization/termination
extern "C" void rt_init();
extern "C" void rt_term();

int helloFromD();

int main(int argc, char** argv)
{
	rt_init();
	int rc = helloFromD();
	rt_term();
	return rc;
}
