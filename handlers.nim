#
# handlers.nim v1.3.2 (2024-03-02)
#   メニューのハンドラ  for haya
#
# メニューハンドラ
import medaka_procs
import std/asynchttpserver
#import std/logging
import std/[os, strtabs, strutils, uri, json, streams, dirs, paths, random]
#import db_connector/db_sqlite
#import body_parser

# デフォルトのプレイリストファイル
const FILELIST = "./filelist.txt"
# (要変更) IP アドレスとポートの指定
#const BASE = "http://localhost:2027/get_file?path="
const BASE = "http://192.168.1.100:2027/get_file?path="

# シーケンスの行をシャッフルする。
proc doShuffle(buffer:seq[string]): seq[string] =
  var lines: seq[string] = buffer
  let n1 = len(buffer) - 1
  var n2 = (len(buffer) / 2).int
  randomize()
  var i = 0
  while i <= n2:
    let p1 = rand(n1)
    let p2 = rand(n1)
    let d = lines[p1]
    lines[p1] = lines[p2]
    lines[p2] = d
    i += 1
  return lines

# 現在のプレイリストファイルを読んでシーケンスとして返す。
proc readFileList(): seq[string] =
  var lines: seq[string] = @[]
  let rstrm = newFileStream(FILELIST, fmRead)
  while not rstrm.atEnd():
    let line = rstrm.readLine()
    if line != "" and line.startswith("#") == false:
      lines.add(line)
  rstrm.close()
  return lines

# 現在のプレイリストファイルをシャッフルする。
proc shuffleList() =
  var lines = readFileList()
  let buffer = doShuffle(lines)
  # ファイル保存
  let wstrm = newFileStream(FILELIST, fmWrite)
  for p in buffer:
    wstrm.writeLine(p)
  wstrm.close()
  return

# プレイリスト一覧を得る。
proc getPlaylists(): string =
  var options = ""
  var s = ""
  for p in walkDir("./playlist"):
    let path = p.path.string
    s = "<option>" & path & "</option>"
    options &= s
  return options






# ビデオ画面 (先頭の動画)
proc index*(req: Request): HandlerResult =
  let hash = parseQuery(req.url.query)
  if hash.hasKey("shuffle"):
    shuffleList()
  var args = newStringTable()
  var lines: seq[string] = @[]
  let rstrm = newFileStream(FILELIST, fmRead)
  var first = rstrm.readLine()
  while first == "" or first.startswith("#") :
    first = rstrm.readLine()
  rstrm.close()
  var url = BASE & first
  args["url"] = url
  args["n"] = "1"
  args["message"] = first
  let (status, content) = templateFile("./templates/index.html", args)
  result = (status, content, htmlHeader())

# ファイル取得 (パスで指定)
proc get_file*(req: Request): HandlerResult =
  let hash = parseQuery(req.url.query)
  let path = hash.getQueryValue("path", "")
  result = sendFile(path)

# ビデオ画面 (番号で指定)
proc next*(req: Request): HandlerResult =
  var args = newStringTable()
  let hash = parseQuery(req.url.query)
  var n = parseInt(hash.getQueryValue("n", "1"))
  var lines: seq[string] = readFileList()
  var path = ""
  if len(lines) > n:
    path = lines[n]
    n += 1
    args["url"] = BASE & path
    args["n"] = $n
    args["message"] = path
    let (status, content) = templateFile("./templates/index.html", args)
    result = (status, content, htmlHeader())
  else:
    let content = "<p>End of files. <a href=\"/\">Rewind</a>"
    result = (Http500, "<p>End of files</p><p style=\"font-size:3em;\"><a href=\"/\">Go to first video.</a></p>", htmlHeader())

# 設定
proc settings*(req: Request): HandlerResult =
  var args = newStringTable()
  if req.reqMethod == HttpGET: # GET
    args["message"] = ""
    args["folder"] = ""
    let (status, content) = templateFile("./templates/settings.html", args)
    result = (Http200, content, htmlHeader())
  else: # POST
    let hash = parseQuery(req.body)
    let folder = hash.getQueryValue("folder", "")
    if folder == "":
      return (Http500, "folder is empty", textHeader())
    let s = hash.getQueryValue("shuffle", "")
    let shuffle = (s != "")
    # ファイル一覧を取得する。
    var buffer: seq[string] = @[]
    for f in walkDir(folder.Path):
      if f.kind == pcDir:
        continue
      let (dir, name, ext) = splitFile(f.path)
      if ext != ".mp4":
        continue
      buffer.add(f.path.string)
    # シャッフル
    if shuffle:
      buffer = doShuffle(buffer)
    # ファイル保存
    let wstrm = newFileStream(FILELIST, fmWrite)
    for p in buffer:
      wstrm.writeLine(p)
    wstrm.close()
    args["folder"] = folder
    args["message"] = "動画一覧ファイルが更新されました。"
    let (status, content) = templateFile("./templates/settings.html", args)
    result = (Http200, content, htmlHeader())
  return
  
# プレイリスト
proc playlist*(req: Request): HandlerResult =
  if req.reqMethod != HttpGET:
    return (Http400, "400 Bad Request", textHeader())
  var args = newStringTable()
  args["message"] = ""
  args["options"] = getPlaylists()
  args["savefile"] = ""
  let (status, content) = templateFile("./templates/playlist.html", args)
  result = (Http200, content, htmlHeader())
  return
  
# プレイリストのロード
proc load_playlist*(req: Request): HandlerResult =
  if req.reqMethod != HttpPOST:
    return (Http400, "400 Bad Request", textHeader())
  var args = newStringTable()
  let hash = parseQuery(req.body)
  var loadfile = hash.getQueryValue("loadfile", "")
  loadfile = loadfile.replace("\\", "/")
  if loadfile == "":
    return (Http500, "500 loadfile is empty.", textHeader())
  writeLine(stderr, loadfile)
  flushFile(stderr)
  let content = readFile(loadfile)
  writeFile("./filelist.txt", content)
  args["message"] = "プレイリスト '" & loadfile & "' をロードしました。"
  args["options"] = getPlaylists()
  args["savefile"] = ""
  let (status, html) = templateFile("./templates/playlist.html", args)
  result = (Http200, html, htmlHeader())
  return

# プレイリストの保存
proc save_playlist*(req: Request): HandlerResult =
  if req.reqMethod != HttpPOST:
    return (Http400, "400 Bad Request", textHeader())
  var args = newStringTable()
  let hash = parseQuery(req.body)
  let savefile = hash.getQueryValue("savefile", "")
  if savefile == "":
    return (Http500, "500 savefile is empty.", textHeader())
  let content = readFile("./filelist.txt")
  writeFile("./playlist/" & savefile, content)
  args["message"] = "プレイリスト '" & savefile & "' を保存しました。"
  args["options"] = getPlaylists()
  args["savefile"] = savefile
  let (status, html) = templateFile("./templates/playlist.html", args)
  result = (Http200, html, htmlHeader())
  return
      
      
# テストでメインとして実行
when isMainModule:
  # proc post_request_xml*(body: string, headers: HttpHeaders): HandlerResult
  var status: HttpCode
  var content: string
  var ret_headers: HttpHeaders
  var headers = newHttpHeaders({"content-type":"application/xml"})
  var body = """<?xml version="1.0"?>
<data>
 <id>10</id>
 <name>James Bond</name>
</data>"""
  (status, content, ret_headers) = post_request_xml(body, headers)
  echo status
  echo content
  echo ret_headers

