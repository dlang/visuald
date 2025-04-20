<img src="/doc/images/vd_logo.png?format=raw" width="72"> Visual D
==================================================================

This is the README file for Visual D, a 
Visual Studio package providing both project management and language services

Copyright (c) 2010-2025 by Rainer Schuetze, All Rights Reserved

Visual D aims at providing seamless integration of the D programming language
into Visual Studio. 

For installer download, more documentation and build instructions, please visit https://rainers.github.io/visuald/visuald/StartPage.html.
Use forum https://forum.dlang.org/group/ide for questions and the D bug tracker https://github.com/dlang/visuald/issues to report issues.


Major Features
---------------
* Custom Project management
  - all DMD command line options accessible
  - support for GDC and LDC
  - support for resource compiler
  - custom build commands
  - pre/post custom build steps
  - automatic dependency generation
  - automatic link between dependent projects
  - new project templates

* Integration with VC projects
  - seamless integration through build customization
  - DMD and LDC command line options accessible
  - parallel compilation

* Debugger
  - VS debugger extension providing D expression evaluation
  - integrates mago, a debug engine dedicated to D
  - integrates cv2pdb for debugging executables built with the Digital Mars toolchain

* Language Service
  - syntax highlighting with special version/debug and token string support
  - underlining of syntactical errors 
  - semantic analysis for code completion, goto definition and tool tips
  - import statement completion
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

* Other
  - symbol/file search window
  - profiler window 
  - C++ to D conversion wizard 
  - [dustmite](https://github.com/CyberShadow/DustMite) integration
  - disassembly view synchronized with source code
  
* Supported Visual Studio versions
  - VS 2008 - VS 2022, Community, Professional or Enterprise versions
  
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
- cv2pdb: https://github.com/rainers/cv2pdb by Rainer Schuetze
- mago: https://github.com/rainers/mago by Aldo Nunez/Rainer Schuetze
- DParser: https://github.com/aBothe/D_Parser by Alexander Bothe

Installation
------------

The click-through-installer will guide you through the installation process. 
The installer lets you select the Visual Studio Version for which you want 
Visual D to be installed. It will always install for all users, not only for 
a single user.

To compile your application, you must have DMD, LDC or GDC installed.
For LDC and GDC, after installation you must setup Visual D to find them: see
Tools->Options->Projects and Solutions->Visual D Settings->LDC Directories
and GDC Directories, respectively.

Changes
-------
For documentation on the changes between this version and
previous versions, please see the file CHANGES.

Building Visual D
-----------------
In a nutshell:

- install the Visual Studio SDK
- start Visual Studio VS 2013+ and load solution visuald_vs10.sln
- select configuration "Debug COFF32|Win32"
- build project "build"
- build project "VisualD"

For more information, visit
https://rainers.github.io/visuald/visuald/BuildFromSource.html

More Information
----------------
For more information on installation, a quick tour of Visual D with some
screen shots and feedback, please visit the project home for Visual D at 
(https://rainers.github.io/visuald/visuald/StartPage.html).

There's a forum dedicated to IDE discussions (https://forum.dlang.org/group/digitalmars.D.ide), where you can leave your comments and suggestions.
Bug reports can be filed to the [issues](https://github.com/dlang/visuald/issues) 
of the repository.

Have fun,
Rainer Schuetze
