#todo http tracker scrape: https://wiki.theory.org/BitTorrentSpecification#Tracker_.27scrape.27_Convention

import uri, net, asyncdispatch, httpclient, tables, sequtils, strutils
import bencode
import ./types
import ./core
import ./globals

proc getHttpScrapeUrl(announceUrl: Uri): Uri =
  let url = $announceUrl
  let pos = url.rfind('/')
  return parseUri(url[0..pos] & url[pos+1..^1].replace("announce","scrape"))

proc httpTrackerAnnounce*(info_hash: string, tracker: Uri): Future[seq[PeerAddr]] {.async.} =
  echo "http " & $tracker
  echo "scrape is " & getHttpScrapeUrl(tracker).hostname
  let anDec = bdecode await newAsyncHttpClient().getContent(tracker).withTimeoutEx(TRACKER_TIMEOUT)
  if anDec.d.hasKey(be"peers"): #if we get bencoded peerlist format, or compact format
    result = if anDec.d["peers"].kind == bkList: anDec.d["peers"].l.mapIt((parseIpAddress(it.d["ip"].s), it.d["port"].i.Port))
  elif anDec.d["peers"].kind == bkStr: anDec.d["peers"].s.parseBinlangPeerList() else: @[]

template httpTrackerScrape*(infoHash: string, tracker: Uri): Future[seq[(uint32,uint32,uint32)]] =
  httpTrackerScrape(@[infoHash], tracker)

proc httpTrackerScrape*(info_hashes: seq[string], tracker: Uri): Future[seq[(uint32,uint32,uint32)]] {.async.} =
  let scrapeUrl = tracker ? info_hashes.mapIt(("info_hash", it))
  echo scrapeUrl
  let scrDec = bdecode await newAsyncHttpClient().getContent(tracker.getHttpScrapeUrl()).withTimeoutEx(TRACKER_TIMEOUT)
  echo scrDec

when isMainModule:
  echo getHttpScrapeUrl(parseUri("https://tracker.nanoha.org:443/announce"))
  #try:
  let hash = parseHexStr("5613c9adf88f66970d926d148e77273e97d74d23")
  let url = getHttpScrapeUrl(parseUri("http://tracker.files.fm:6969/announce"))
  echo url
  echo waitFor httpTrackerScrape(hash, getHttpScrapeUrl(url))
 # except:
   # echo "exception"