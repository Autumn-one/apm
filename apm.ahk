;@Ahk2Exe-ConsoleApp
#SingleInstance Force
#include <stdlib>
#include utils.ahk
#include tools\env.ahk
#include tools\everything.ahk
#include package.json.ahk
#Include tools\http.ahk
#Include tools\JSON.ahk
SetWorkingDir A_ScriptDir



; 管理员权限运行
full_command_line := DllCall("GetCommandLine", "str")

if not (A_IsAdmin or RegExMatch(full_command_line, " /restart(?!\S)"))
{
    try
    {
        if A_IsCompiled
            Run '*RunAs cmd.exe /k "' A_ScriptFullPath '" ' A_Args.Join(" ") ' /restart'
        else
            Run '*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '" ' A_Args.Join(" ")
    }
    ExitApp
}


apm_version := "0.0.1"

isChinese := GetLocaleLanguage() = "zh-CN"

useBuiltInEverything := false ; 是否使用类内置的Everything

; 检查编码确认 utf-8, 如果有控制台那么设置成这个编码
if (encode := DllCall("GetConsoleOutputCP")) != 0 && encode != 65001{
    DllCall("SetConsoleOutputCP", "UInt", 65001)
}

;@region -----------这里获取ahk的安装目录----------------------------------
; 先查看注册表中记录的是否有对应的信息,如果没有在去用everything来搜索

InstallDir := RegRead("HKLM\SOFTWARE\AutoHotkey", "InstallDir", "")
ahkDirPath := InstallDir ? InstallDir.ConcatP("v2") : ""

if ahkDirPath == ""{
    try{
        ; 先初始化Everything,这个是必要的
        if !Everything.IsDBLoaded() && !Everything.HasEverythingProcess() {
            useBuiltInEverything := true
            Everything.RunEverything()
            tiploading := () => ToolTip(isChinese ? "初始化Everything中..." : "Initialize Everything...")
            SetTimer tiploading, 50
            if Everything.WaitDBLoaded(20000) {
                SetTimer tiploading, 0
                ToolTip
                Everything.SaveDB()
            }else{
                SetTimer tiploading, 0
                ToolTip
                msgbox(isChinese ? "Everything初始化失败,请手动选择AutoHotkey.exe所在的目录或重新安装Everything" : "Everything failed to initialize, please manually select the directory where AutoHotkey.exe is located or reinstall Everything")
            }
        }
    
        if Everything.IsDBLoaded() {
            dir1Arr := Everything.GetAllDir("wfn:AutoHotkey.exe")
            dir2Arr := Everything.GetAllDir("wfn:AutoHotkey32.exe")
            dir3Arr := Everything.GetAllDir("wfn:AutoHotkey64.exe")
            dirArr := dir1Arr.Intersect(dir2Arr, dir3Arr)
            if dirArr.Length == 1 {
                ahkDirPath := dirArr[1]
            }
        }
    
        if !IsSet(ahkDirPath){
            msgbox(isChinese ? "我们无法确认AutoHotkey.exe文件的目录位置,请你手动选择" : "We cannot confirm the directory location of the AutoHotkey.exe file, please select it manually")
            ahkDirPath := DirSelect("*",3, isChinese ? "请选择AutoHotkey.exe所在目录" : "Select the directory where AutoHotkey.exe resides")
        }
    }
    
    
    if useBuiltInEverything {
        if Everything.Exit() = 0 && ProcessExist("everything.exe") {
            ProcessClose("everything.exe")
        }
    }
    
}


if !ahkDirPath{
    return
}

;@endregion
;---------获取ahk安装位置结束----------------------------------

; 解析命令行参数
argObj := ParserArgs()

packageJson := {} ; packagejson的对象
npmrc := ["https://registry.npmjs.org","https://registry.npmmirror.com","https://registry.yarnpkg.com","https://r.cnpmjs.org","https://mirrors.cloud.tencent.com/npm"] ; npm镜像


%argObj.command.Concat("Handle")%()

installHandle(){
    ; 安装
    (argObj.packageNames.Length) ? installPackages() : installDeps()
}

installPackages(){
    initHandle() ; 初始化package.json
    ; println("安装若干个安装包:", argObj.packageNames)
    ; install的时候要查看package.json
    pkgJson := JsonLoad(A_InitialWorkingDir.ConcatP("package.json"))
    deps := pkgJson.Has('devDependencies') ? pkgJson["devDependencies"] :  Map()

    for packageName in argObj.packageNames {
        normalPkgName := normalizePackageName(packageName)
        if packageName.TrimLeft("@").Includes("@") || !deps.Has(normalPkgName) {
            try{
                ; 先解析包名和版本号
                getPkgNameAndVersion(packageName, &pkgName, &pkgVersion, &pkgNameAtVersion)
                ; 根据包名和版本号来下载具体的包
                downloadPackage(pkgName, pkgVersion)
                ; 这里将下载好的包放到当前的目录下面
                installPackageToLocal(pkgName, pkgVersion, pkgNameAtVersion)
                ; 将当前的下载的包保存到package.json
                savePackageInfo(pkgName, pkgVersion)
    
            }catch Error as err{
                println(err)
                println(isChinese ? packageName.Concat("下载失败") : packageName.Concat(" download failed"))
            }
        }else{
            try {
                ; 根据包名和版本号来下载具体的包
                pkgVersion := deps[normalPkgName]
                downloadPackage(normalPkgName, pkgVersion)
                ; 这里将下载好的包放到当前的目录下面
                installPackageToLocal(normalPkgName, pkgVersion, normalPkgName "@" pkgVersion)
                ; 将当前的下载的包保存到package.json
                savePackageInfo(normalPkgName, pkgVersion)
            }catch Error as err{
                println(err)
                println(isChinese ? packageName.Concat("下载失败") : packageName.Concat(" download failed"))
            }
        }
        
    }
}

installDeps(){
    ; 解析当前目录的所有依赖,要通过package.json
    pkgJson := JsonLoad(A_InitialWorkingDir.ConcatP("package.json"))

    if !pkgJson.Has("devDependencies") {
        println(isChinese ? "当前目录中的项目未查询到依赖" : "No dependencies found for the project in the current directory.")
        return
    }
    for pkgName, pkgVersion in pkgJson["devDependencies"] {
        downloadPackage(pkgName, pkgVersion)
        ; 这里将下载好的包放到当前的目录下面
        installPackageToLocal(pkgName, pkgVersion, pkgName "@" pkgVersion)
    }
}

; https://docs.npmjs.com/cli/v10/configuring-npm/package-json
initHandle(){
    global npmrc
    ; 初始化项目,就是创建一个package.json, 在当前目录下创建一个
    if !FileExist(A_InitialWorkingDir.ConcatP("package.json")) {
        FileAppend packageJsonText.Replace("packageName", A_InitialWorkingDir.BaseName()), A_InitialWorkingDir.ConcatP("package.json"), "utf-8"
    }
    ; 获取package.json
    pkg := JSON.Load(FileRead(A_InitialWorkingDir.ConcatP("package.json"),"utf-8"))
    if pkg.Has("npmrc") {
        npmrc := npmrc.Union(pkg["npmrc"]).Unique()
    }
}

updateHandle(){

    initHandle() ; 初始化package.json
    pkgJson := JsonLoad(A_InitialWorkingDir.ConcatP("package.json"))
    deps := pkgJson.Has('devDependencies') ? pkgJson["devDependencies"] :  Map()

    for packageName in argObj.packageNames {
        try{
            ; 先解析包名和版本号
            getPkgNameAndVersion(packageName, &pkgName, &pkgVersion, &pkgNameAtVersion)
            ; 根据包名和版本号来下载具体的包
            downloadPackage(pkgName, pkgVersion)
            ; 这里将下载好的包放到当前的目录下面
            installPackageToLocal(pkgName, pkgVersion, pkgNameAtVersion)
            ; 将当前的下载的包保存到package.json
            savePackageInfo(pkgName, pkgVersion)

        }catch Error as err{
            println(err)
            println(isChinese ? packageName.Concat("下载失败") : packageName.Concat(" download failed"))
        }
        
    }
}

removeHandle(){
    ; 删除包可能是本地也可能是全局
    if !argObj.packageNames.Length {
        return
    }
    baseDir := argObj.globalFlag ? ahkDirPath.ConcatP("Lib") : A_InitialWorkingDir.ConcatP("Lib")

    if argObj.globalFlag {
        for pkgName in argObj.packageNames {
            try FileDelete(baseDir.ConcatP(pkgName ".ahk"))
        }    
    }else{
        pkgJson := JsonLoad(baseDir.SplitRight("\",1)[1].ConcatP("package.json"))
        deps := pkgJson.Has("devDependencies") ? pkgJson["devDependencies"] : Map()
        for pkgName in argObj.packageNames {
            try FileDelete(baseDir.ConcatP(pkgName ".ahk"))

            if deps.Has(normalizePackageName(pkgName)) {
                deps.Delete(normalizePackageName(pkgName))
            }
        }
        
        JsonDump(pkgJson, baseDir.SplitRight("\",1)[1].ConcatP("package.json"))
    }
    
}

versionHandle(){
    println(isChinese ? "当前apm版本为:".Concat(apm_version) : "The current APM version is:".Concat(apm_version))
}

listHandle(){
    if argObj.globalFlag {
        ; 列出全局的包
        println(isChinese ? "全局安装的包列表:" : "List of globally installed packages:")
        loop files ahkDirPath.ConcatP("Lib", "*"), "D" {
            println("- " A_LoopFileName)
        }
        return
    }

    ; 列出本地的包
    println(isChinese ? "本地安装的包列表:" : "List of locally installed packages:")
    localLibDir := A_InitialWorkingDir.ConcatP("Lib")
    loop files localLibDir.ConcatP("*") {
        codeText := FileRead(A_LoopFileFullPath, "utf-8")
        RegExMatch(codeText, "<([^>]+)>", &ms)
        println("- " ms[1].SplitRight("\", 1)[1])
    }


}

; 根据用户输入的包名获取包名和包的版本号
getPkgNameAndVersion(inputPkgName, &pkgName, &pkgVerison, &pkgNameAtVersion?){
    ; 正常化包名
    packageName := normalizePackageName(inputPkgName)
    ; 包名不带版本
    pkgName := packageName.SplitRight("@", 1)[1]

    
    pkgVerison := getPackageVersion(packageName)
    if !pkgVerison {
        println(isChinese ? packageName.Concat("版本获取失败,请检查网络并重试.") : packageName.Concat("Failed to obtain the version. Please check the network and try again."))
        return
    }
    pkgNameAtVersion := pkgName "@" pkgVerison
    
    
}

; 安装包到本地的目录下面,其实就是在当前目录下面创建一个 Lib 并且给出对应的内容
installPackageToLocal(pkgName, pkgVersion, pkgNameAtVersion){
    ; 如果pkgName以ahk-开头那么删除这个开头
    if pkgName.StartsWith("ahk-"){
        /**@var {String} pkgName*/
        pkgName := pkgName.Split("ahk-", 1)[2]
    }
    localPath := argObj.globalFlag ? ahkDirPath.ConcatP("Lib") : A_InitialWorkingDir.ConcatP("Lib") ; 这里要判断全局
    if !DirExist(localPath) {
        DirCreate(localPath)
    }
    ; 读取package.json中的main信息,这个信息确定入口
    pkgJsonPath := ahkDirPath.ConcatP("Lib",pkgNameAtVersion, "package.json")
    pkg := JsonLoad(pkgJsonPath)

    if pkg.Has("main") {
        libFilePath := localPath.ConcatP(pkgName ".ahk")
        if FileExist(libFilePath) {
            try FileDelete(libFilePath)
        }
        FileAppend("#Include <" pkgNameAtVersion "\" pkg["main"].SplitRight(".", 1)[1] ">", libFilePath, "utf-8")
        return
    }
    println(isChinese ? pkgNameAtVersion.Concat("没有导出模块.") : pkgNameAtVersion.Concat("No export module."))

}

; 将安装的包的信息保存到package.json
savePackageInfo(pkgName, pkgVersion){
    ; 全局安装不保存package.json信息
    if argObj.globalFlag {
        return 
    }
    ; 判断当前目录有没有package.json如果没有就创建,有就添加
    localPkgJsonPath := A_InitialWorkingDir.ConcatP("package.json")
    if !FileExist(localPkgJsonPath) {
        initHandle() ; 没有package.json 就说明还没初始化,那么初始化一下
    }
    pkg := JsonLoad(localPkgJsonPath)
    if !pkg.Has("devDependencies") {
        pkg["devDependencies"] := Map()
    }

    pkg["devDependencies"][pkgName] := pkgVersion

    JsonDump(pkg, localPkgJsonPath)

}

JsonLoad(filePath){
    text := FileRead(filePath, "utf-8")
    return JSON.Load(text)
}

JsonDump(jsonObj, filePath){
    try FileDelete(filePath)
    FileAppend(JSON.Dump(jsonObj, 4), filePath, "utf-8")
}

downloadPackage(pkgName, pkgVersion){
    
    pkgNameAtVersion := pkgName "@" pkgVersion
    println(isChinese ? "正在下载: ".Concat(pkgNameAtVersion, "...") : "downloading: ".Concat(pkgNameAtVersion, "..."))

    ; 下载前看一下是不是已经有了,如果有了就不下载
    if DirExist(ahkDirPath.ConcatP("Lib",pkgNameAtVersion)) {
        println(isChinese ? pkgNameAtVersion.Concat("下载完成") : pkgNameAtVersion.Concat("download completes"))
        return
    }
    
    ; 先创建downloads目录用来存放下载的文件
    if !DirExist(ahkDirPath.ConcatP("downloads")){
        try{
            DirCreate(ahkDirPath.ConcatP("downloads"))
        }catch{
            msgbox(isChinese ? "下载目录创建失败,请确认有足够权限并重试!" : "Failed to create the download directory. Please confirm that you have sufficient permissions and try again!")
            return
        }
    }

    ; 这里肯定拿到版本了,直接下载
    for rc in npmrc {
        packageUrl := rc.Concat("/", pkgName, "/-/", pkgName.Split("/")[-1], "-", pkgVersion, ".tgz")
        distFile := ahkDirPath.ConcatP("downloads", pkgNameAtVersion ".tgz")
        tempDir := ahkDirPath.ConcatP("downloads","Temp" A_Now A_MSec) ; 用于解压的临时目录
        ; println("下载的包url:", packageUrl)
        ; println("下载到的目录:", distFile)
        try{
            Download(packageUrl, distFile)
            ; println("下载成功")
            ; 如果下载成功就解压文件到Lib
        }catch{
            ; println("下载失败继续")
            continue
        }

        unzipCmd := "7z.exe x `"".Concat(
            distFile, '"',
            ' -o"',
            tempDir,
            '"'
        )

        ; 7z 解压tgz文件要解压两次,沃日,真tmd恶心啊草tmd.
        unzipCmd2 := "7z.exe x `"".Concat(
            tempDir.ConcatP(pkgNameAtVersion ".tar"), '" ',
            "-o`"", tempDir, '"'
        )
        ; println("两条命令分别为")
        ; println(unzipCmd)
        ; println(unzipCmd2)
        ret := StdoutToVar(unzipCmd)
        if ret.ExitCode != 0 {
            ; 清除操作
            if DirExist(tempDir){
                try DirDelete(tempDir, 1)
            }
            msgbox(isChinese ? pkgNameAtVersion.Concat("1.包解压失败!请检查后重试!`n", ret.Output) : pkgNameAtVersion.Concat("Package decompression failed! Please check and try again!`n", ret.Output))
            ExitApp
        }

        ret2 := StdoutToVar(unzipCmd2)

        if ret2.ExitCode != 0 {
            ; 清除操作
            if DirExist(tempDir){
                try DirDelete(tempDir, 1)
            }
            msgbox(isChinese ? pkgNameAtVersion.Concat("2.包解压失败!请检查后重试!`n", ret.Output) : pkgNameAtVersion.Concat("Package decompression failed! Please check and try again!`n", ret.Output))
            ExitApp
        }

        
        
        ; 移动到对应的目录并重新命名
        packageDistDir := ahkDirPath.ConcatP("Lib", pkgNameAtVersion) ; 目标文件夹
        try{
            DirMove(tempDir.ConcatP("package"), packageDistDir, 2)
            try DirDelete(tempDir, true)
            try DirDelete(ahkDirPath.ConcatP("downloads"), true)
            break
        }catch{
            msgbox(isChinese ? pkgNameAtVersion.Concat("重命名失败!请检查后重试!") : pkgNameAtVersion.Concat("Renaming failed! Please check and try again!"))
            ExitApp
        }
    }
    println(isChinese ? pkgNameAtVersion.Concat("下载完成") : pkgNameAtVersion.Concat("download completes"))
    ; 如果下载成功并解包成功就继续判断并下载对应的依赖项
    ; 读取下面的package.json,拿到依赖列表并下载
    try {
        packageText := FileRead(packageDistDir.ConcatP("package.json"), "utf-8")
        pkg := JSON.Load(packageText)
        if pkg.Has("devDependencies") && pkg["devDependencies"].Length != 0 {
            for pkgN, pkgV in pkg["devDependencies"] {
                downloadPackage(pkgN, pkgV)
            }
        }
    }catch {
        msgbox(isChinese ? pkgNameAtVersion.Concat("包依赖读取失败,请检查后重试!") : pkgNameAtVersion.Concat("Packet dependency read failed, please check and try again!"))
        ExitApp
    }
    
}

; 把少的ahk-补回来,但是有可能带有版本号
normalizePackageName(packageName){
    if packageName.StartsWith("ahk-") || packageName.StartsWith("@ahk/"){
        return packageName
    }
    return "ahk-".Concat(packageName)
}

getPackageVersion(packageName){
    ; 这个方法里面传入的一定是进过正常化的包名
    tempName := packageName.StartsWith("@ahk/") ? packageName[2, -1] : packageName

    tempArr := tempName.Split("@")
    versionStr := ""
    if tempArr.Length >= 2 {
        versionStr := tempArr[-1]
    }else{
        versionStr := "latest"
    }

    if versionStr.IncludeSome("latest", "beta", "dev") {
        ; 这种情况要请求获取版本号
        return getVersionByNpmRC(packageName.SplitRight("@", 1)[1], versionStr)
    }else{
        ; 这种直接返回
        return versionStr
    }
}

; 根据npmrc和包名获取版本号
getVersionByNpmRC(packageName, versionStr){
    for rc in npmrc {
        try{
            text := request(rc.Concat("/", packageName))   
            RegExMatch(text, '"dist-tags":(\{[^}]*?\})', &output)
            ret := JSON.Load(output[1])
            return ret[versionStr]
        }
    }
    return ""
}


