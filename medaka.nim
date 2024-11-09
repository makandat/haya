# Medaka server  v1.2.1 (2024-01-30)
import std/asynchttpserver
import std/asyncdispatch
import std/[paths, strtabs, json, mimetypes, strutils, strformat, logging]
import handlers

const VERSION = "1.2.1"
const USE_PORT:uint16 = 2027
const CONFIG_FILE = "medaka.json"
const LOG_FILE = "medaka.log"
let START_MSG = fmt"Start medaka server v{VERSION} ..."

# read medaka.json
proc readSettings(): StringTableRef =
  let settings = newStringTable()
  let s = readFile(CONFIG_FILE)
  let data = parseJson(s)
  for x in data.pairs:
    settings[x.key] = x.val.getStr("")
  return settings

# initialize logger
proc initLogger() =
  let file = open(LOG_FILE, fmAppend)
  let logger = newFileLogger(file, fmtStr=verboseFmtStr)
  addHandler(logger)

# return static file as Response
proc staticFile(filepath: string): (HttpCode, string, HttpHeaders) =
  try:
    let (dir, name, ext) = splitFile(Path(filepath))
    let m = newMimeTypes()
    var mime = m.getMimeType(ext)
    if ext == ".txt" or ext == ".html":
      mime = mime & "; charset=utf-8"
    var buff: string = readFile(filepath)
    result = (Http200, buff, newHttpHeaders({"Content-Type":mime}))
  except Exception as e:
    let message = e.msg
    error(message)
    result = (Http500, fmt"<h1>Internal error</h1><p>{message}</p>", newHttpHeaders({"Content-Type":"text/html; charset=utf-8"}))

# Callback on Http request
#   TODO: You must change below, when you create your own application. 
proc callback(req: Request) {.async.} =
  #info(req.url.path)
  echo req.url.path
  var status = Http200
  var content = ""
  var headers = newHttpHeaders({"Content-Type":"text/html; charset=utf-8"})
  let settings = readSettings()
  var filepath = ""
  let htdocs = settings["html"]
  let templates = settings["templates"]
  if req.url.path == "" or req.url.path == "/":
    filepath = htdocs & "/index.html"
  else:
    filepath = htdocs & "/" & req.url.path
  # ディスパッチ処理
  #   最初のページ
  if req.url.path == "/":
    (status, content, headers) = handlers.index(req)
  #  ファイル取得 (パス名指定) /get_file
  elif req.url.path == "/get_file":
    (status, content, headers) = handlers.get_file(req)
  #  ファイル取得 (番号指定) /next
  elif req.url.path == "/next":
    (status, content, headers) = handlers.next(req)
  #  設定 /settings
  elif req.url.path == "/settings":
    (status, content, headers) = handlers.settings(req)
  #  プレイリスト /playlist
  elif req.url.path == "/playlist":
    (status, content, headers) = handlers.playlist(req)
  #  プレイリストロード /load_playlist
  elif req.url.path == "/load_playlist":
    (status, content, headers) = handlers.load_playlist(req)
  #  プレイリスト保存 /save_playlist
  elif req.url.path == "/save_playlist":
    (status, content, headers) = handlers.save_playlist(req)
  else: # その他はエラーにする。
    status = Http403 # Forbidden
    headers = newHttpHeaders({"Content-Type":"text/html"})
    content = "<h1>Error: This path is fobidden.</h1><p>" & req.url.path & "</p>"
  # 応答を返す。
  await req.respond(status, content, headers)

#
#  Start as main
#  =============
when isMainModule:
  initLogger()
  var server = newAsyncHttpServer()
  server.listen(Port(USE_PORT))
  echo START_MSG & "\n URL: http://localhost:" & $USE_PORT
  info START_MSG
  while true:
    if server.shouldAcceptRequest():
      waitFor server.acceptRequest(callback)
    else:
      echo "Sleep"
      waitFor sleepAsync(500)

