#TODO DHT tracking - steal from here https://github.com/status-im/nim-libp2p-dht
#TODO encryption http://wiki.vuze.com/w/Message_Stream_Encryption
#TODO UTP protocol - steal from https://github.com/status-im/nim-eth/tree/master/eth/utp
#TODO geoip for peers
#TODO IPV6 trackers
#todo support for multiple network interfaces + get external ip for all nics and report all ips to tracker
#todo basic bittorrent specification

import std/[asyncdispatch, asyncnet, net, httpclient, socketstreams, streams, os, uri, tables, strutils, sequtils, random, sha1, endians]
import bencode, binarylang, bitvector
from itertools import chunked #just for "chunked", get rid of it nothing else used
import comptest
import timeit

import ./types
import ./udp_tracker2
import ./http_tracker
import ./core
import ./globals
import ./peer
import protocol/udpTrackerStruct

import terminal

import sugar

func genHandshake(hash: var string): string =
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

  let sha1 = tDict.d["info"].bencode().secureHash()
  t.sha1 = newString(20); copyMem(t.sha1[0].addr, sha1.unsafeAddr, 20); #todo remove when nim can convert array[uint8] to string https://github.com/nim-lang/Nim/issues/14810
  t.sha1hex = t.sha1.toHex()
  t.pieceSize = tDict.d["info"].d["piece length"].i.uint

  if tDict.d["info"].d.hasKey(be"files"):
    #t.files = newSeq[TorrentFile](0); 
    var curOffset = 0'u
    for file in tDict.d["info"].d["files"].l:
      let path = file.d["path"].l[0..^1].mapIt(it.s).join("/")
      let size = file.d["length"].i.uint
      t.files.add(TorrentFile(path: path, offset: curOffset, size: size))
      curOffset += size
    t.size = t.files[^1].offset + t.files[^1].size
  else:
    t.files.add(TorrentFile(path: tDict.d["info"].d["name"].s, offset: 0'u, size: tDict.d["info"].d["length"].i.uint))
    t.size = tDict.d["info"].d["length"].i.uint
  t.numPieces = t.size div t.pieceSize + (t.size mod t.pieceSize != 0).uint
  t.numBlocks = t.size div max_block_size + (t.size mod max_block_size != 0).uint
  t.pcsHashes = collect(for x in tDict.d["info"].d["pieces"].s.chunked(20): x.join("")) 
  t.urls = if tDict.d.hasKey(be"url-list"): tDict.d["url-list"].l.mapIt(parseUri(it.s)) else: @[]
  t.trackers = if tDict.d.hasKey(be"announce-list"): tDict.d["announce-list"].l.mapIt(it.l).concat().mapIt(parseUri(it.s)) #2 maps needed, first one to unpack the list/seq from seq[BencodedObj] 
               elif tDict.d.hasKey(be"announce"):    @[tDict.d["announce"].s.parseUri()] else: @[]  
  t.handshake = genHandshake(t.sha1)
  t.trackerReqURLs = t.trackers.mapIt(if it.scheme.startsWith("http"): it ? {"info_hash": t.sha1, "peer_id": PEER_ID,  "ip": my_ip, "port": $port, "downloaded": "0",
    "uploaded": "0", "left": "0", "event": "started", "compact": "1", "numwant": "200" } else: it)
  
  t.private = if tDict.d["info"].d.hasKey(be"private"): tDict.d["info"].d["private"].i.bool else: false
  t.source = if tDict.d["info"].d.hasKey(be"source"): tDict.d["info"].d["source"].s else: ""
  t.comment = if tDict.d.hasKey(be"comment"): tDict.d["comment"].s else: ""
  t.createdBy = if tDict.d.hasKey(be"created by"): tDict.d["created by"].s else: ""
  t.createdOn = if tDict.d.hasKey(be"creation date"): tDict.d["creation date"].i.uint64 else: 0
  #put some kind of size check like assert t.pieces.len div 20 * t.pieceSize.int == t.size.int

  t.pcsHave = newBitVector[uint](t.numPieces.int)
  t.pcsWant = newBitVector[uint](t.numPieces.int, init = 1)
  t.pcsActive = newBitVector[uint](t.numPieces.int)

  t.blkHave = newBitVector[uint](t.numBlocks.int)
  t.blkWant = newBitVector[uint](t.numBlocks.int, init = 1)
  t.blkActive = newBitVector[uint](t.numBlocks.int)
  
  m.finish()
  await t.updatePeerList() #this needs to be moved someplace else, torrent manager, to not block torrent creation
  return t

proc startPeers(t: Torrent) {.async.} =
  var futs: seq[Future[void]]
  for peerAddr in t.peerList:
    t.conns.add(Peer(host: peerAddr, asocket: newAsyncSocket()))
    futs.add(t.conns[^1].peerLoop(t))
  await all futs

when isMainModule:
    var my_ip = waitFor getMyIp()
    var myTorrent: Torrent
    if paramCount() == 0:
      myTorrent = waitFor Torrent.init(parseUri("file:///home/sgm/Downloads/PostmarketOS V21.12 Phosh 17 Pine64 Pinetab Allwinner 20220420 IMG XZ.torrent"))
    else:
      myTorrent = waitFor Torrent.init(parseUri(paramStr(1)))
    echo "peerlist len will be " & $myTorrent.peerList.len
    echo "peerlist is " & $myTorrent.peerList
    randomize()
    waitFor startPeers(myTorrent)