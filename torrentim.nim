#TODO DHT tracking - steal from here https://github.com/status-im/nim-libp2p-dht
#TODO encryption http://wiki.vuze.com/w/Message_Stream_Encryption
#TODO UTP protocol - steal from https://github.com/status-im/nim-eth/tree/master/eth/utp
#TODO geoip for peers and sort by country distance
#TODO IPV6 trackers
#TODO support for multiple network interfaces + get external ip for all nics and report all ips to tracker
#TODO basic bittorrent specification
#TODO downloading from non seeds, retrying failed pieces, piece verify, seeding, multi file leech/seed

import std/[asyncdispatch, asyncnet, net, httpclient, socketstreams, streams, os, uri, tables, strutils, sequtils, random, sha1, endians, algorithm, paths]
import bencode, binarylang, bitvector
from itertools import chunked #just for "chunked", get rid of it nothing else used
import comptest
import timeit

import ./types
import ./tracker/udp_tracker2
import .//tracker/http_tracker
import ./core
import ./globals
import ./peer
import ./piece
import ./io
import protocol/udpTrackerStruct

import terminal

import sugar

func genHandshake(hash: string): string =
  result = HANDSHAKE_HEADER & hash & PEER_ID

proc connectPeers*(peers: seq[Peer]) {.async.} =
  var futs: seq[Future[seq[PeerAddr]]]

proc getPeerList*(trackerReqUrls: seq[Uri], info_hash: string, timeout = TRACKER_TIMEOUT): Future[seq[PeerAddr]] {.async.} =
  var futs: seq[Future[seq[PeerAddr]]]
  for tracker in trackerReqUrls:
    if tracker.scheme.startsWith("http"):
      futs.add(httpTrackerAnnounce(info_hash, tracker))
    elif tracker.scheme.startsWith("udp"):
      futs.add(udpTrackerAnnounce(info_hash, tracker))
  for i, f in futs:
    try:
      echo "we are awaiting tracker " & $i
      result &= await f
    except CatchableError as e:
       echo "we got an exception at fut " & $i & " " & $e.name & $e.msg
    result = result.deduplicate()
  echo "final result of peerlist is " & $result 

proc updatePeerList*(self: Torrent) {.async.} =
  self.peerList &= await getPeerList(self.trackerReqURLs, self.sha1)
  echo "in update peerlist we have " & $self.peerList

#proc makeTorrentFile*(files, announce: seq[string], comment, cratedBy, name,): string =

proc `<`(x, y: BencodeObj): bool =
  case x.kind:
  of bkStr: return x.s < y.s
  of bkInt: return x.i < y.i
  else: discard

proc `==`(x, y: BencodeObj): bool =
  case x.kind:
  of bkStr: return x.s == y.s
  of bkInt: return x.i == y.i
  else: discard



proc exportTorrent*(files: seq[TorrentFile], name: string, piece_len: uint, pieces: seq[string], private: int, trackers: seq[Uri], optFields, optInfoFields: BencFields = @[]): string =
  var tDict = initOrderedTable[string, BencodeObj]()
  var infoDict = initOrderedTable[string, BencodeObj]()

  if files.len > 1:
    infoDict["files"] = be( files.mapIt( be({
      "length": be(it.size.int),
      "path": be(it.path.string.split(DirSep).mapIt(be(it)))
    })) )
  elif files.len == 1: infoDict["length"] = be(files[0].size.int) 
  infoDict["name"] = be(name)
  infoDict["piece length"] = be(piece_len.int)
  infoDict["pieces"] = be(pieces.join(""))
  if private > -1: infoDict["private"] = be(private) 
  for entry in optInfoFields:
    infoDict[entry[0]] = entry[1]
  #infoDict.sort(system.cmp)
  infoDict.sort do (x, y: tuple[key: string; value: BencodeObj]) -> int: #stolen code, I have no idea how this works
    system.cmp(x.key, y.key)

  if trackers.len>0: tDict["announce"] = be($trackers[0])
  if trackers.len>1: tDict["announce-list"] = be(trackers.mapIt( be (@[be($it)]) ))
  tDict["info"] = be(infoDict)
  for entry in optFields:
    tDict[entry[0]] = entry[1]
  tDict.sort do (x, y: tuple[key: string; value: BencodeObj]) -> int: #stolen code, I have no idea how this works
    system.cmp(x.key, y.key)
  return be(tDict).bEncode()

proc exportTorrent*(t: Torrent): string =
  return exportTorrent(t.files, t.name, t.pieceSize, t.pcsHashes, t.private, t.trackers, t.optFields, t.optInfoFields)

proc init*(_: typedesc[Torrent], src: Uri): Future[Torrent] {.async.} =
  var torrentbytes: string
  if ($src).startsWith("file"):
    torrentBytes = readFile(($src)[7..^1])
  else:
    torrentBytes = await newAsyncHttpClient().getContent(src)
  return await Torrent.init(torrentBytes, src)

proc init*(_: typedesc[Torrent], torrentBytes: string, src: Uri): Future[Torrent] {.async.} =
  var m = monit("first"); m.start()
  var t = result; t = new Torrent #t gets assigned result, which of type Torrent (ref), thus shares the same address with it
  t.sourceUri = src
  var tDict = bdecode(torrentBytes) #decoded torrent benc node tree structure

  t.sha1 = tDict.d["info"].bencode().secureHash()
  #echo repr(sha
  #t.sha1 = newString(20); copyMem(t.sha1[0].addr, sha1.unsafeAddr, 20); #todo remove when nim can convert array[uint8] to string https://github.com/nim-lang/Nim/issues/14810
  t.sha1hex = t.sha1.toHex()
  t.pieceSize = tDict.d["info"].d["piece length"].i.uint

  if tDict.d["info"].d.hasKey("files"):
    var curOffset = 0'u
    for file in tDict.d["info"].d["files"].l:
      let path = file.d["path"].l[0..^1].mapIt(it.s).join($DirSep)
      let size = file.d["length"].i.uint
      t.files.add(TorrentFile(path: path.Path, offset: curOffset, size: size))
      curOffset += size
    t.size = t.files[^1].offset + t.files[^1].size
  else:
    t.files.add(TorrentFile(path: tDict.d["info"].d["name"].s.Path, offset: 0'u, size: tDict.d["info"].d["length"].i.uint))
    t.size = tDict.d["info"].d["length"].i.uint
  t.name = tDict.d["info"].d["name"].s
  t.numPieces = t.size div t.pieceSize + (t.size mod t.pieceSize != 0).uint
  t.numBlocks = t.size div max_block_size + (t.size mod max_block_size != 0).uint
  t.pcsHashes = collect(for x in tDict.d["info"].d["pieces"].s.chunked(20): x.join(""))
  assert t.numPieces == t.pcsHashes.len.uint
  t.webSeedUrls = if tDict.d.hasKey("url-list"): tDict.d["url-list"].l.mapIt(parseUri(it.s)) else: @[]
  t.trackers = if tDict.d.hasKey("announce-list"): tDict.d["announce-list"].l.mapIt(it.l).concat().mapIt(parseUri(it.s)) #2 maps needed, first one to unpack the list/seq from seq[BencodedObj] 
               elif tDict.d.hasKey("announce"):    @[tDict.d["announce"].s.parseUri()] else: @[]  
  t.handshake = genHandshake(t.sha1)
  t.trackerReqURLs = t.trackers.mapIt(if it.scheme.startsWith("http"): it ? {"info_hash": t.sha1.string, "peer_id": PEER_ID,  "ip": my_ip, "port": $port, "downloaded": "0",
    "uploaded": "0", "left": "0", "event": "started", "compact": "1", "numwant": "200" } else: it)
  
  t.private = if tDict.d["info"].d.hasKey("private"): tDict.d["info"].d["private"].i.bool.int else: -1
  t.source = if tDict.d["info"].d.hasKey("source"): tDict.d["info"].d["source"].s else: ""
  t.comment = if tDict.d.hasKey("comment"): tDict.d["comment"].s else: ""
  t.createdBy = if tDict.d.hasKey("created by"): tDict.d["created by"].s else: ""
  t.createdOn = if tDict.d.hasKey("creation date"): tDict.d["creation date"].i.uint64 else: 0

  #storing misc key/val in torrent (excepting essential values that are in torrent object already), so that we may later completely reconstruct the .torrent file from this
  for key, val in tDict.d.pairs:
    if not (key in ["announce", "announce-list", "info" ]): # ["info", "comment"]):
      t.optFields.add((key, val))

  for key, val in tDict.d["info"].d.pairs:
    if not (key in ["files", "length", "name", "piece length","pieces", "private"]):
      t.optFields.add((key, val))

  #[echo "total size " & $t.size
  echo "blocks number " & $t.numBlocks
  echo "piece number " & $t.numPieces
  echo "piece size " & $t.pieceSize
  let x = readLine(stdin)]#

  #echo readBlock((0.uint, 0.uint, 16308.uint), t)

  m.finish()
  return t

proc startPeers(t: Torrent) {.async.} =
  var futs: seq[Future[void]]
  for peerAddr in t.peerList:
    t.conns.add(Peer(host: peerAddr, asocket: newAsyncSocket()))
    futs.add(t.conns[^1].peerLoop(t))
  await all futs

proc startTorrent(t: Torrent) {.async.} =

  t.filesWanted = newBitVector[uint](t.numBlocks.int, init = 1)

  t.blkHave = newBitVector[uint](t.numBlocks.int)
  t.blkWant = newBitVector[uint](t.numBlocks.int, init = 1)
  t.blkActive = newBitVector[uint](t.numBlocks.int)

  t.pcsHave = newBitVector[uint](t.numPieces.int)
#  t.pcsWant = newBitVector[uint](t.numPieces.int, init = 1)
  #t.pcsWant = files2PieceMap(t.files, t.filesWanted, t.pieceSize, t.numPieces)
  t.pcsWant = files2PieceMap(t)
  t.pcsActive = newBitVector[uint](t.numPieces.int)


  t.blkRequester = dispatchClosure(t)
  t.basePath = absolutePath("dl".Path / t.name.Path)
  discard existsOrCreateDir(t.basePath.string)  

  waitFor t.makeEmptyFiles()
  waitFor t.updatePeerList()
  waitFor startPeers(t)


when isMainModule:
    var my_ip = waitFor getMyIp()
    var myTorrent: Torrent
    if paramCount() == 0:
      #myTorrent = waitFor Torrent.init(parseUri("file://" & absolutePath("./test/bittorrent-v2-hybrid-test.torrent")))
      #myTorrent = waitFor Torrent.init(parseUri("file://" & absolutePath("./test/debian-11.6.0-amd64-netinst.iso.torrent")))
      myTorrent = waitFor Torrent.init(parseUri("file://" & absolutePath("./test/Teslagrad Remastered [FitGirl Repack].torrent")))
      
    else:
      myTorrent = waitFor Torrent.init(parseUri(paramStr(1)))
    #writeFile("cats.txt", exportTorrent(myTorrent)) 
    let x = readLine(stdin)
    randomize()
    waitFor startTorrent(myTorrent)
    
