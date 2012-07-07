c:\l\dmd-1.056\windows\bin\dmd.exe -g tlb2idl.d oleaut32.lib uuid.lib snn.lib kernel32.lib
if errorlevel 1 goto xit
m:\s\d\cv2pdb\trunk\bin\debug\cv2pdb -D1 tlb2idl.exe tlb2idl_pdb.exe 
:xit