;@Ahk2Exe-ConsoleApp
#SingleInstance Force
#include <stdlib>
#include utils.ahk
#include <env>
#include Lib\everything.ahk
#include package.json.ahk
#Include Lib\http.ahk
#Include Lib\JSON.ahk
SetWorkingDir A_ScriptDir

isChinese := GetLocaleLanguage() = "zh-CN"

useBuiltInEverything := false ; 是否使用类内置的Everything

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

    if !IsSet(ahkPath){
        msgbox(isChinese ? "我们无法确认AutoHotkey.exe文件的目录位置,请你手动选择" : "We cannot confirm the directory location of the AutoHotkey.exe file, please select it manually")
        ahkDirPath := DirSelect("*",3, isChinese ? "请选择AutoHotkey.exe所在目录" : "Select the directory where AutoHotkey.exe resides")
    }
}


if useBuiltInEverything {
    if Everything.Exit() = 0 && ProcessExist("everything.exe") {
        ProcessClose("everything.exe")
    }
}

if !ahkDirPath{
    return
}



; 解析命令行参数
argObj := ParserArgs()

packageJson := {} ; packagejson的对象
npmrc := [] ; npm镜像


%argObj.command.Concat("Handle")%()

installHandle(){
    ; 安装
    (argObj.packageNames.Length) ? installPackages() : installDeps()
}

installPackages(){
    initHandle() ; 初始化package.json
    ; println("安装若干个安装包:", argObj.packageNames)
    for packageName in argObj.packageNames {
        try{
            downloadPackage(packageName)
        }catch{
            println(isChinese ? packageName.Concat("下载失败") : packageName.Concat(" download failed"))
        }
    }
}


downloadPackage(packageName){
    
    println(isChinese ? "正在下载: ".Concat(packageName) : "downloading: ".Concat(packageName))
    ; 正常化包名
    packageName := normalizePackageName(packageName)
    ; 包名不带版本
    packageNameNoVersion := packageName.SplitRight("@", 1)[1]

    
    curVersion := getPackageVersion(packageName)
    if !curVersion {
        println(isChinese ? packageName.Concat("版本获取失败,请检查网络并重试.") : packageName.Concat("Failed to obtain the version. Please check the network and try again."))
        return
    }

    ; 下载前看一下是不是已经有了,如果有了就不下载
    if DirExist(ahkDirPath.ConcatP("Lib",packageNameNoVersion "@" curVersion)) {
        println(isChinese ? packageName.Concat("下载完成") : packageName.Concat("download completes"))
        return
    }
    

    ; 这里肯定拿到版本了,直接下载
    for rc in npmrc {
        packageUrl := rc.Concat("/", packageName, "/-/", packageName.Split("/")[-1], "-", curVersion, ".tgz")
        distFile := ahkDirPath.ConcatP("downloads", packageName ".tgz")
        tempDir := ahkDirPath.ConcatP("Temp" A_Now A_MSec) ; 用于解压的临时目录
        try{
            Download(packageUrl, distFile)
            ; 如果下载成功就解压文件到Lib
        }catch{
            continue
        }

        ret := StdoutToVar("7z.exe ".Concat(
            distFile,
            ' -o"',
            tempDir,
            '"'
        ))
        if ret != 0 {
            ; 清除操作
            if DirExist(tempDir){
                try DirDelete(tempDir, 1)
            }
            msgbox(isChinese ? packageName.Concat("包解压失败!请检查后重试!`n", ret.Output) : packageName.Concat("Package decompression failed! Please check and try again!`n", ret.Output))
            ExitApp
        }
        ; 移动到对应的目录并重新命名
        packageDistDir := ahkDirPath.ConcatP("Lib", packageNameNoVersion "@" curVersion) ; 目标文件夹
        try{
            DirMove(tempDir.ConcatP("package"), packageDistDir)
            break
        }catch{
            msgbox(isChinese ? packageName.Concat("重命名失败!请检查后重试!") : packageName.Concat("Renaming failed! Please check and try again!"))
            ExitApp
        }
    }
    println(isChinese ? packageName.Concat("下载完成") : packageName.Concat("download completes"))
    ; 如果下载成功并解包成功就继续判断并下载对应的依赖项
    ; 读取下面的package.json,拿到依赖列表并下载
    try {
        packageText := FileRead(packageDistDir.ConcatP("package.json"), "utf-8")
        pkg := JSON.Load(packageText)
    }catch {
        msgbox(isChinese ? packageName.Concat("包依赖读取失败,请检查后重试!") : packageName.Concat("Packet dependency read failed, please check and try again!"))
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


installDeps(){
    println("安装所有的依赖")
}

; https://docs.npmjs.com/cli/v10/configuring-npm/package-json
initHandle(){
    global npmrc
    ; 初始化项目,就是创建一个package.json, 在当前目录下创建一个
    if !FileExist(A_InitialWorkingDir.ConcatP("package.json")) {
        FileAppend packageJsonText.Replace("packageName", A_InitialWorkingDir.BaseName()), A_InitialWorkingDir.ConcatP("package.json"), "utf-8"
    }
    ; 获取package.json
    packageJson := JSON.Load(FileRead(A_InitialWorkingDir.ConcatP("package.json"),"utf-8"))
    npmrc := packageJson["npmrc"]
}

updateHandle(){

}

removeHandle(){

}

versionHandle(){

}


