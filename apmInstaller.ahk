;@Ahk2Exe-ConsoleApp
#SingleInstance Force
#Requires AutoHotkey v2.0 
#include <stdlib>
#include <env>

; 管理员权限运行
full_command_line := DllCall("GetCommandLine", "str")

if not (A_IsAdmin or RegExMatch(full_command_line, " /restart(?!\S)"))
{
    try
    {
        if A_IsCompiled
            Run '*RunAs "' A_ScriptFullPath '" ' A_Args.Join(" ") ' /restart'
        else
            Run '*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '" ' A_Args.Join(" ")
    }
    ExitApp
}

apmInstallerVersion := "0.1"

isChinese := GetLocaleLanguage() = "zh-CN"

; 检查编码确认 utf-8
if (encode := DllCall("GetConsoleOutputCP")) != 0 && encode != 65001{
    DllCall("SetConsoleOutputCP", "UInt", 65001)
}

println(isChinese ? "请选择安装目录..." : "Select an installation directory...")
; 让用户选择安装目录,并且将目录添加到环境变量
installDir := DirSelect("*",3, isChinese ? "请选择安装目录" : "Select an installation directory")

if !installDir { ; 操作取消
    return
}

try {
    ; 将所有的必要文件释放到这个目录, 但有可能出现问题,如果有问题就提示并退出
    FileInstall("Lib\everything.exe", installDir.ConcatP("everything.exe"), true)
    FileInstall("Lib\Everything64.dll", installDir.ConcatP("Everything64.dll"), true)
}catch{
    msgbox(isChinese ? "安装过程出现错误,请检查后重试!" : "An error occurred during installation. Please check and try again!")
    return
}
; 写入环境变量
Env_SystemAdd("Path",installDir, "REG_SZ")