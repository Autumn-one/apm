
request(url){
    whr := ComObject('WinHttp.WinHttpRequest.5.1')
    whr.Open('GET', url, 1)
    ; whr.SetRequestHeader('Content-Type', 'application/json; charset=utf-8')
    whr.Send()
    whr.WaitForResponse()
    return whr.ResponseText
}