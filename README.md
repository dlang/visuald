<img src="/doc/images/vd_logo.png?format=raw" width="72">
Visual D
============================================================

This is the README file for Visual D, a 
Visual Studio package providing both project management and language services

Copyright (c) 2010-2013 by Rainer Schuetze, All Rights Reserved

Visual D aims at providing seamless integration of the D programming language
into Visual Studio. 

For installer download, more documentation and build instructions, please visit http://rainers.github.io/visuald/visuald/StartPage.html.
Use forum http://forum.dlang.org/group/digitalmars.D.ide for questions and the D bug tracker https://d.puremagic.com/issues/ to report issues.


Major Features
---------------
* Project management
  - all DMD and GDC command line options accessable
  - support for x64 builds with GDC
  - support for resource compiler
  - custom build commands
  - pre/post custom build steps
  - automatic dependency generation
  - automatic link between dependend projects
  - new project templates

* Debugger
  - integrates cv2pdb for seamless integration with the VS native debugger 
  - integrates mago, a debug engine dedicated to D

* Language Service
  - syntax highlighting with special version/debug and token string support
  - underlining of syntactical errors 
  - simple word-completion
  - import statement completion
  - goto definition (using JSON file from compilation)
  - parameter info tooltips 
  - smart indentation
  - comment/uncomment selection 
  - highlight/jump-to matching braces
  - code snippets
  - display of scope at caret position
  - code outlining
  - paste visually from clipboard ring
  - code definition window
  - search and replace dialog based on D tokenizer
  - browse information displayed in object browser and class view 
  - help on language and runtime library
  - semantic analysis for code completion and tool tips

* Other
  - symbol/file search window
  - profiler window 
  - C++ to D conversion wizard 
    
* Supported Visual Studio versions
  - VS 2005
  - VS 2008
  - VS 2010
  - VS 2012
  - VS 2013
  Unfortunately, Express versions of Visual Studio do not support this 
  kind of extensions. Use the Visual Studio Shell instead:
  - VS 2008 Shell: http://www.microsoft.com/en-us/download/details.aspx?id=9771
  - VS 2010 Shell: no longer available
  - VS 2012 Shell: http://www.microsoft.com/en-us/download/details.aspx?id=30670
                 + http://www.microsoft.com/en-us/download/details.aspx?id=30663
  
* Includes tools to
  - convert some idl/h files of the Windows SDK to D
  - convert all idl/h files from the Visual Studio Integration SDK to D
  - convert C++ code to D (which was targeted at machine-translating
    the DMD front end to D, but this was abandoned)
  - convert Java code to D (which was targeted at machine-translating
    parts of the Eclipse plugin Descent to D, but this was abandoned)
  
* Completely written in D2

License information
-------------------

This code is distributed under the terms of the Boost Software License, Version 1.0.
For more details, see the full text of the license in the file LICENSE_1.0.txt.

The installer comes with a number of additional products:
- cv2pdb: http://dsource.org/projects/cv2pdb by Rainer Schuetze
- mago: http://dsource.org/projects/mago_debugger by Aldo Nunez
- DParser: https://github.com/aBothe/D_Parser by Alexander Bothe

Building Visual D
-----------------
In a nutshell:

- install the Visual Studio SDK
- start Visual Studio and load solution visuald_vs9.sln (VS 2008) or
  visuald_vs10.sln (VS 2010)
- build project "build"
- build project "VisualD"

For more information, visit
http://rainers.github.io/visuald/visuald/BuildFromSource.html


Installation
------------

The click-through-installer will guide you through the intallation process. 
The installer lets you select the Visual Studio Version for which you want 
Visual D to be installed. It will always install for all users, not only for 
a single user.

To compile your application, you must have DMD installed.

For debugging applications, you should also install cv2pdb which is now 
included in the Visual D installer. Please make sure, changes to 
Common7\Packages\Debugger\autoexp.dat do not mix with previous manual 
installations of cv2pdb. 

Unfortunately, if you are using the Visual Studio Shell, it misses one file,
that is needed for the conversion of the debug information by cv2pdb. This 
is msobj80.dll for VS2008 and msobj100.dll for VS2010 and must be extracted 
from a standard installation, the Visual C Express edition or the Windows SDK.
You might also find it installed by other Microsoft products. 

Changes
-------
For documentation on the changes between this version and
previous versions, please see the file CHANGES.

More Information
----------------
For more information on installation, a quick tour of Visual D with some
screen shots and feedback, please visit the project home for Visual D at 
[http://rainers.github.io/visuald/visuald/StartPage.html](http://rainers.github.io/visuald/visuald/StartPage.html).

There's a forum dedicated to IDE discussions (http://forum.dlang.org/group/digitalmars.D.ide), where you can leave your comments and suggestions.
Bug reports can be filed to the [D bugzilla database](http://d.puremagic.com/issues/enter_bug.cgi?product=D) 
for Component VisualD.

Have fun,
Rainer Schuetze
