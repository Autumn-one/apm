
;@Ahk2Exe-ConsoleApp
#Requires AutoHotkey v2.0 
SetWorkingDir A_ScriptDir
#Include package.json.ahk
#include <stdlib>
#include Lib\http.ahk
#Include Lib\JSON.ahk
#Include package.json.ahk
; text := request("https://registry.npmmirror.com/a-calc")

; RegExMatch(text, '"dist-tags":(\{[^}]*?\})', &output)
; ret := JSON.Load(output[1])
; ; println(ret)
; ; for k, v in ret {
; ;     println(k, v)
; ; }

; println("c:\".ConcatP("abc", "dde"))

ret := JSON.load(packageJsonText)

; println(ret)

; println(ret.Has("name"))

