// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module dimagelist;

import stringutil;

mixin(extractDefines(import("resources.h")));

const kImageBmp = "BMP_DIMAGELIST";

const kImageDSource = 0;
const kImageProject = 1;
const kImageFolderClosed = 2;
const kImageFolderOpened = 3;
const kImageResource = 4;
const kImageDocument = 5;
const kImageScript = 6;

const IDC_TOOLBAR = 1010;
const IDC_FILEWHEEL = 1011;
const IDC_FILELIST = 1012;
const IDC_FILELISTHDR = 1013;
const IDC_FANINLIST = 1014;
const IDC_FANOUTLIST = 1015;

// menu ID
const IDM_COLUMNLISTBASE = 0x100;

// Miscellaneous IDs
const ID_SUBCLASS_HDR  = 0x100;
