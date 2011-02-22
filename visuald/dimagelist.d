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

const IDC_FINDTEXT      = 2000;
const IDC_REPLACETEXT   = 2001;
const IDC_FINDMATCHCASE = 2002;
const IDC_REPLACECASE   = 2003;
const IDC_FINDLOOKIN    = 2004;
const IDC_FINDDIRECTION = 2005;
const IDC_FINDNEXT      = 2006;
const IDC_REPLACE       = 2007;
const IDC_REPLACEALL    = 2008;
const IDC_FINDCLOSE     = 2009;
const IDC_FINDMATCHBRACES = 2010;
const IDC_FINDINCCOMMENT  = 2011;

// menu ID
const IDM_COLUMNLISTBASE = 0x100;

// Miscellaneous IDs
const ID_SUBCLASS_HDR  = 0x100;
