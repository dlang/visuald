// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2016 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

using System;
using System.Runtime.InteropServices; // DllImport

namespace vdext15
{
    public class IID
    {
        public const string IVisualDHelper15 = "002a2de9-8bb6-484d-9915-7e4ad4084715";
        public const string VisualDHelper15 = "002a2de9-8bb6-484d-AA15-7e4ad4084715";
    }

    [ComVisible(true), Guid(IID.IVisualDHelper15)]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IVisualDHelper15
    {
    }

    [ComVisible(true), Guid(IID.VisualDHelper15)]
    [ClassInterface(ClassInterfaceType.None)]
    public partial class VisualDHelper15 : IVisualDHelper15
    {
        public VisualDHelper15()
        {
        }

        public void Dispose()
        {
        }
	}
}
