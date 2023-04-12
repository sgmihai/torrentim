import uri, tables, strutils, sequtils
import ./types
import bencode

type MagnetKind = enum
  ed2k = "ed2k", bitprint = "bitprint", tth = "tree:tiger", btih = "btih", btmh = "btmh", sha1 = "sha1", md5 = "md5", kzhash = "kzhash"

type Magnet = object
  kind: MagnetKind
  hash: string
  xt: string
  dn: string
  xl: uint64
  tr: seq[Uri]
  ws: seq[Uri]
  acs: seq[Uri]
  xs: seq[Uri]
  kt: string
  so: seq[uint]
  xpe: seq[string]

proc expandRanges(s: string): seq[uint] =
  for i in s.split(","):
    let r = i.split("-")
    if r.len == 2:
      for x in parseUInt(r[0])..parseUInt(r[1]): result.add(x)
    elif r.len>2: continue
    else: result.add(parseUInt(i))

proc flattenRanges(x: seq[uint]): string =
  func rangeParse(a,b: uint): string =
    if b - a >= 2:
      result = $a & "-" & $b
    elif b - a == 1: result = $a & "," & $b
    else: result = $b
    result &= ","

  var current_start, current_end = x[0]
  for i in 1..x.len-1:
    if x[i] == current_end + 1:
      current_end = x[i]
    else:
      result.add(rangeParse(current_start,current_end))
      current_start = x[i]; current_end = x[i]
  result.add(rangeParse(current_start, current_end))
  result.delete(result.len-1,result.len-1) #remvoe trailing ','

proc parseMagnet(magnetUri: string): Magnet =
  if not magnetUri.startsWith("magnet:?"): return
  let uri = magnetUri[8..^1].decodeUrl()
  var m = result
  for param in uri.split("&"):
    let parts = param.split("=")
    if parts.len != 2: continue
    let (key, value) = (parts[0], parts[1])
    case key:
      of "xt":
        m.xt = value
        let firstPos = value.find(":")
        let lastPos = value.rfind(":")
        m.kind = parseEnum[MagnetKind]((value[firstPos+1..lastPos-1]))
        m.hash = value[lastPos+1..^1]
      of "dn": m.dn = value
      of "xl": m.xl = value.parseUInt()
      of "tr": m.tr.add(parseUri(value))
      of "ws": m.ws.add(parseUri(value))
      of "acs": m.acs.add(parseUri(value))
      of "xs": m.xs.add(parseUri(value))
      of "kt": m.kt = value
      of "so": m.so = expandRanges(value)
      of "x.pe": m.xpe.add(value)
      else: echo "unrecognized value"
  return m

proc createMagnet(m: Magnet): string =
  var uri = "magnet:?"
  if m.xt.len > 0: uri &= "xt=" & m.xt & "&"
  if m.dn.len > 0: uri &= "dn=" & m.dn & "&"
  if m.xl > 0: uri &= "xl=" & $m.xl & "&"
  if m.tr.len > 0: uri &= m.tr.mapIt("tr=" & encodeUrl($it)).join("&") & "&"
  if m.ws.len > 0: uri &= m.ws.mapIt("ws=" &  encodeUrl($it)).join("&") & "&"
  if m.acs.len > 0: uri &= m.acs.mapIt("as=" & encodeUrl($it)).join("&") & "&"
  if m.xs.len > 0: uri &= m.xs.mapIt("xs=" & $it).join("&") & "&"
  if m.kt.len > 0: uri &= "kt=" & m.kt & "&"
  if m.so.len > 0: uri &= "so=" & flattenRanges(m.so) & "&"
  if m.xpe.len > 0: uri &= m.xpe.mapIt("x.pe=" & it).join("&") & "&"
  uri.delete(uri.len-1,uri.len-1) #remove trailing '&'
  return uri

 # t.trackers = decodeUrl(m).split("&tr=")[1..^1].mapIt(parseUri(it))
 # t.sha1hex = m[m.find("btih:")+5..m.find("&")-1]
  #t.sha1 = t.sha1hex.parseHexStr()
  #t.name = m[m.find("&dn=")+4..m.find("&tr=")-1]
  #return t

proc magnet2Torrent(m: Magnet): Torrent =
  var t = new Torrent
  if m.kind == MagnetKind.btih or m.kind == MagnetKind.btmh:
    t.sha1 = m.hash
    t.name = m.dn
    t.size = m.xl
    t.trackers = m.tr
    #t.webseeds = m.ws
    #t.filesenabled = m.so..
    #t.peerList <- m.xpe

proc saveTorrent(t: string): string =
  let
    data = be({
      be"interval": be(1800),
      be"min interval": be(900),
      be"peers": be("\x0a\x0a\x0a\x05\x00\x80"),
      be"complete": be(20),
      be"incomplete": be(0),
    })
  echo data

when isMainModule:
  let test = "magnet:?xt=urn:btih:56d30dfd1c5aad9ad75082b2d9c30a9452613c6b&dn=Skyrim.Special.Edition-jc141&tr=udp%3a%2f%2ftracker.opentrackr.org%3a1337%2fannounce&tr=udp%3a%2f%2f9.rarbg.com%3a2810%2fannounce&tr=udp%3a%2f%2ftracker.openbittorrent.com%3a6969%2fannounce&tr=http%3a%2f%2ftracker.openbittorrent.com%3a80%2fannounce&tr=udp%3a%2f%2ftracker.torrent.eu.org%3a451%2fannounce&tr=udp%3a%2f%2fopentracker.i2p.rocks%3a6969%2fannounce&tr=https%3a%2f%2fopentracker.i2p.rocks%3a443%2fannounce&tr=udp%3a%2f%2fopen.stealth.si%3a80%2fannounce&tr=udp%3a%2f%2fvibe.sleepyinternetfun.xyz%3a1738%2fannounce&tr=udp%3a%2f%2ftracker1.bt.moack.co.kr%3a80%2fannounce&tr=udp%3a%2f%2ftracker.zemoj.com%3a6969%2fannounce&tr=udp%3a%2f%2ftracker.tiny-vps.com%3a6969%2fannounce&tr=udp%3a%2f%2ftracker.theoks.net%3a6969%2fannounce&tr=udp%3a%2f%2ftracker.swateam.org.uk%3a2710%2fannounce&tr=udp%3a%2f%2ftracker.internetwarriors.net%3a1337%2fannounce&tr=udp%3a%2f%2ftracker.leechers-paradise.org%3a6969%2fannounce&tr=udp%3a%2f%2fcoppersurfer.tk%3a6969%2fannounce&tr=udp%3a%2f%2ftracker.zer0day.to%3a1337%2fannounce"
  let testh ="magnet:?xt=urn:btih:631a31dd0a46257d5078c0dee4e66e26f73e42ac&xt=urn:btmh:1220d8dd32ac93357c368556af3ac1d95c9d76bd0dff6fa9833ecdac3d53134efabb&dn=bittorrent-v1-v2-hybrid-test"
  let test2 = "magnet:?xt=urn:btmh:1220caf1e1c30e81cb361b9ee167c4aa64228a7fa4fa9f6105232b28ad099f3a302e&dn=bittorrent-v2-test"
  let test3 = "magnet:?xt=urn:btih:6d4795dee70aeb88e03e5336ca7c9fcf0a1e206d&dn=debian-11.6.0-amd64-netinst.iso&tr=http%3a%2f%2fbttracker.debian.org%3a6969%2fannounce&ws=https%3a%2f%2fcdimage.debian.org%2fcdimage%2farchive%2f11.6.0%2famd64%2fiso-cd%2fdebian-11.6.0-amd64-netinst.iso&ws=https%3a%2f%2fcdimage.debian.org%2fcdimage%2frelease%2f11.6.0%2famd64%2fiso-cd%2fdebian-11.6.0-amd64-netinst.iso&ws=https%3a%2f%2fgemmei.ftp.acc.umu.se%2fcdimage%2frelease%2f11.6.0%2famd64%2fiso-cd%2fdebian-11.6.0-amd64-netinst.iso&so=0,2,4,6-8,11-15,101-119,120,121,122,124,125,126,128,129"
  
  echo parseMagnet(test3)
  echo ""
  echo createMagnet(parseMagnet(test3))

  #echo test
  #echo decodeUrl(test).split("&tr=").mapIt(parseUri(it))