#Requires AutoHotkey v2.0 
#include <stdlib>

class Everything {
    static EvDll := ""
    static __New(){
            this.EvDll := DllCall("LoadLibrary", "Str", "Everything64.dll", "Ptr")
    }
    static GetCount(keyword){
        try {
            DllCall("Everything64.dll\Everything_SetSearch", "Str", keyword)
        } catch Error as e {
            ExitApp
        }
        DllCall("Everything64.dll\Everything_Query", "int64", 1)
        return DllCall("Everything64.dll\Everything_GetNumResults")
    }
    static GetAllDir(keyword){
        arr := []
        Loop this.GetCount(keyword)
        {
            dirPath := DllCall("Everything64.dll\Everything_GetResultPath", "Int", A_index - 1, "Str")
            arr.Push(dirPath)
        }
        return arr
    }
    static HasEverythingProcess(){
        DetectHiddenWindows 1
        ret := ProcessExist("everything.exe")
        DetectHiddenWindows 0
        return ret
    }
    static RunEverything(){
        cmdstr := "everything.exe -startup "
        if FileExist(A_ScriptDir "\Everything.db") {
            cmdStr := cmdStr "-db " '"' A_ScriptDir "\Everything.db" '"'
        }
        Run cmdStr
    }
    static WaitDBLoaded(timeout := 10000){
        start := time.Now()
        while this.IsDBLoaded() = 0 {
            now := time.Now()
            if now - start >= timeout {
                return 0
            }
            Sleep(200)
        }
        return 1
    }
    static IsDBLoaded(){
        return DllCall("Everything64.dll\Everything_IsDBLoaded", "Int") 
    }
    static ReBuildDB(){
        return DllCall("Everything64.dll\Everything_RebuildDB", "Int") 
    }
    static Exit(){
        return DllCall("Everything64.dll\Everything_Exit", "Int") 
    }
    static GetLastError(){
        return DllCall("Everything64.dll\Everything_GetLastError", "Int") 
    }
    static SaveDB(){
        return DllCall("Everything64.dll\Everything_SaveDB", "Int")
    }
}