// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.dimagelist;

import stdext.string;

mixin(extractDefines(import("resources.h")));

const kImageDSource = 0;
const kImageProject = 1;
const kImageFolderClosed = 2;
const kImageFolderOpened = 3;
const kImageResource = 4;
const kImageDocument = 5;
const kImageScript = 6;
const kImageDisabled = 7;

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

const IDC_WIZ_WRITEINTERMED = 2020;
const IDC_WIZ_INPUTTPYE     = 2021;
const IDC_WIZ_INPUTFILES    = 2022;
const IDC_WIZ_KEYWORDPREFIX = 2023;
const IDC_WIZ_REPLACEPRE    = 2024;
const IDC_WIZ_REPLACEPOST   = 2025;
const IDC_WIZ_VERSIONS      = 2026;
const IDC_WIZ_EXPANSIONS    = 2027;
const IDC_WIZ_VALUETYPES    = 2028;
const IDC_WIZ_CLASSTYPES    = 2029;
const IDC_WIZ_OUTPUTDIR     = 2030;
const IDC_WIZ_LOAD          = 2031;
const IDC_WIZ_SAVE          = 2032;
const IDC_WIZ_CONVERT       = 2033;
const IDC_WIZ_INPUTDIR      = 2034;
const IDC_WIZ_PACKAGEPREFIX = 2035;
const IDC_WIZ_CODEHDR       = 2036;

// menu ID
const IDM_COLUMNLISTBASE = 0x100;

// Miscellaneous IDs
const ID_SUBCLASS_HDR  = 0x100;

// entries in the image list "completionset.bmp" through the envireonment
enum CSIMG_PROT_PUBLIC    = 0;
enum CSIMG_PROT_LETTER    = 1;
enum CSIMG_PROT_BRIGHT    = 2;
enum CSIMG_PROT_PROTECTED = 3;
enum CSIMG_PROT_PRIVATE   = 4;
enum CSIMG_PROT_LINK      = 5;

enum CSIMG_CLASS          = 0;  // combine with CSIMG_PROT for modifier
enum CSIMG_PACKAGE        = 6;
enum CSIMG_DELEGATE       = 12;
enum CSIMG_ENUM           = 18;
enum CSIMG_ENUMMEMBER     = 24;
enum CSIMG_BLITZ          = 30;
enum CSIMG_FUNCTION       = 36;
enum CSIMG_FIELD          = 42;
enum CSIMG_INTERFACE      = 48;
enum CSIMG_UNKNOWN2       = 54;
enum CSIMG_UNKNOWN3       = 60;
enum CSIMG_UNKNOWN4       = 66;
enum CSIMG_MEMBER         = 72;
enum CSIMG_MEMBERS        = 78;
enum CSIMG_UNKNOWN5       = 84;
enum CSIMG_NAMESPACE      = 90;
enum CSIMG_UNKNOWN6       = 96;
enum CSIMG_PROPERTY       = 102;
enum CSIMG_STRUCT         = 108;
enum CSIMG_TEMPLATE       = 114;
enum CSIMG_UNKNOWN7       = 120;
enum CSIMG_ALIAS          = 125;
enum CSIMG_UNION          = 126;
enum CSIMG_STRUCT3        = 132;
enum CSIMG_FIELD2         = 138;
enum CSIMG_STRUCT4        = 144;
enum CSIMG_UNKNOWN8       = 150;
enum CSIMG_JMEMBER        = 156;
enum CSIMG_JFIELD         = 162;
enum CSIMG_JSTRUCT        = 168;
enum CSIMG_JNAMESPACE     = 174;
enum CSIMG_JINTERFACE     = 180;
enum CSIMG_STOP           = 186; // series of single bitmaps follow

enum CSIMG_DMODULE        = 194;
enum CSIMG_DFOLDER        = 201;
enum CSIMG_KEYWORD        = 206;
