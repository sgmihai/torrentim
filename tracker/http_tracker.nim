#todo http tracker scrape: https://wiki.theory.org/BitTorrentSpecification#Tracker_.27scrape.27_Convention

import uri, net, asyncdispatch, httpclient, tables, sequtils, strutils
import bencode
import ../types
import ../core
import ../globals

proc getHttpScrapeUrl(announceUrl: Uri): Uri =
  let url = $announceUrl
  let pos = url.rfind('/')
  return parseUri(url[0..pos] & url[pos+1..^1].replace("announce","scrape"))

proc httpTrackerAnnounce*(info_hash: string, tracker: Uri, params: httpAnnounceParams = @[]): Future[seq[PeerAddr]] {.async.} =
  let anDec = bdecode await newAsyncHttpClient().getContent(tracker ? (toSeq(tracker.query.decodeQuery()) & params)).withTimeoutEx(TRACKER_TIMEOUT) #FIXME once https://github.com/nim-lang/Nim/issues/19782
  echo $tracker & " got " & $anDec
  if anDec.d.hasKey("peers"): #if we get bencoded peerlist format, or compact format
    result = if anDec.d["peers"].kind == bkList: anDec.d["peers"].l.mapIt((parseIpAddress(it.d["ip"].s), it.d["port"].i.Port))
  elif anDec.d["peers"].kind == bkStr: anDec.d["peers"].s.parseBinlangPeerList() else: @[]
  if anDec.d["peers"].kind == bkStr: echo "we have string/compact peers" elif anDec.d["peers"].kind == bkList: echo "we have bencoded"
  echo "result is " & $result

template httpTrackerScrape*(infoHash: string, tracker: Uri): Future[seq[(uint32,uint32,uint32)]] =
  httpTrackerScrape(@[infoHash], tracker)

proc httpTrackerScrape*(info_hashes: seq[string], tracker: Uri): Future[seq[(uint32,uint32,uint32)]] {.async.} =
  let scrapeUrl = tracker ? info_hashes.mapIt(("info_hash", it))
  echo scrapeUrl
  let scrDec = bdecode await newAsyncHttpClient().getContent(scrapeUrl).withTimeoutEx(TRACKER_TIMEOUT)
  echo scrDec

when isMainModule:
  discard
  let my_ip = waitFor getMyIp()
  let hash = parseHexStr("aad00c145cfecb4990de397c9ac4239909accc48")
  let url = parseUri("http://reactor.filelist.io//announce") ? {"info_hash": hash, "peer_id": PEER_ID,  "ip": my_ip, "port": $port, "downloaded": "0",
    "uploaded": "0", "left": "0", "event": "started", "compact": "1", "numwant": "200", }
  echo waitFor httpTrackerAnnounce(hash, url)
  #echo getHttpScrapeUrl(parseUri("https://tracker.nanoha.org:443/announce"))
  #try:
  #let hash = parseHexStr("5613c9adf88f66970d926d148e77273e97d74d23")
  #let url = getHttpScrapeUrl(parseUri("http://reactor.filelist.io//announce"))
  #let url = parseUri("http://reactor.filelist.io//announce")
  #let hash = parseHexStr("f635ab36e63931534aaf45c7a0136f21e381e101")
  #let hash = parseHexStr("f9e79195751356e256ac6b3b3d2ddc41fca9a6b3")
  

  #echo url
  #echo waitFor httpTrackerScrape(hash, getHttpScrapeUrl(url))
  #echo waitFor httpTrackerAnnounce(hash, url)
  # except:
  # echo "exception"
  
  #example qbittorrent request:
  #http://ramjet.speedapp.to//announce?info_hash=t%e6%11f%1b1%d9%aeZ%db%cd%3f%cc%ce%ea%bat%26%5e%60&peer_id=-qB4500-0VsceHrrP5kP&port=32682&uploaded=0&downloaded=0&left=4500658469&corrupt=0&key=54484F63&event=started&numwant=200&compact=1&no_peer_id=1&redundant=0