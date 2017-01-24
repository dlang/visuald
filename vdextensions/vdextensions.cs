// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2016 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

using System;
using System.Runtime.InteropServices; // DllImport

using Microsoft.VisualStudio.Text.Editor;
using Microsoft.VisualStudio.Editor;
using Microsoft.VisualStudio.TextManager.Interop;
using Microsoft.VisualStudio.Shell.Interop;

namespace vdextensions
{
    public class IID
    {
        public const string IVisualDHelper = "002a2de9-8bb6-484d-9910-7e4ad4084715";
        public const string VisualDHelper = "002a2de9-8bb6-484d-AA10-7e4ad4084715";
    }

    [ComVisible(true), Guid(IID.IVisualDHelper)]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IVisualDHelper
    {
        void GetTextOptions(IVsTextView view, out int flags, out int tabsize, out int indentsize);
    }

    [ComVisible(true), Guid(IID.VisualDHelper)]
    [ClassInterface(ClassInterfaceType.None)]
    public partial class VisualDHelper : IVisualDHelper
    {
        static IVsEditorAdaptersFactoryService editorFactory;

        public static bool setFactory(IVsEditorAdaptersFactoryService factory)
        {
            editorFactory = factory;
            return true;
        }

        public VisualDHelper()
        {
        }

        public void Dispose()
        {
        }

        public void GetTextOptions(IVsTextView view, out int flags, out int tabsize, out int indentsize)
        {
            if (editorFactory == null)
                throw new COMException();

            IWpfTextView wv = editorFactory.GetWpfTextView(view);
            if (wv == null || wv.Options == null)
                throw new COMException();

            bool spaces = wv.Options.GetOptionValue<bool>(DefaultOptions.ConvertTabsToSpacesOptionId);
            flags = spaces ? 1 : 0;
            tabsize = wv.Options.GetOptionValue<int>(DefaultOptions.TabSizeOptionId);
            indentsize = wv.Options.GetOptionValue<int>(DefaultOptions.IndentSizeOptionId);
        }

    }
}
