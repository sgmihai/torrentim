#specification: https://www.libtorrent.org/udp_tracker_protocol.html
#todo - use alternative libraries to std, like:
 #https://github.com/zero-functional/zero-functional - for map and other functional programming stuff - zero cost
 #https://github.com/status-im/nim-chronos - maybe? instead of asyncdispatch
 #hardware accelerate sha1 lib?

#todo - add timeout-done, exception. and figure out how to return timeout error back (option types?)
#todo - add return of host cannot be resolved
#todo - add return of tracker error message 
#todo - figure out if the net code is correct- that is, if further reads from the socket don't need to happen to make sure no data is missed
#todo - implement action=3 - tracker error messages reporting
#todo - implement extensions1 = authentication. 2 = request string.
#todo - If no response to a request is received within 15 seconds, resend the request. If no reply has been received after 60 seconds, stop retrying.
#todo - see if protobuf is a better fit
#todo - ipv6 tracker

import net, uri, asyncdispatch, asyncnet, random, strutils, std/[sequtils, sha1]
import ../types
import ../core
import ../globals
include ../protocol/udpTrackerStruct
import binarylang

template udpTrackerPing(pingTempl: untyped) {.dirty.} =
  var pingStr = newStringBitStream(); pingTempl.put(pingStr, ping); pingStr.setPosition(0)
  discard await socket.sendTo(tracker.hostname, Port(parseInt(tracker.port)), pingStr.readAll()).withTimeout(1500)

template udpTrackerPong(pongTempl: untyped) {.dirty.} =
  let resp = await socket.recvFrom(UDP_MAX_SIZE).withTimeoutEx(TRACKER_TIMEOUT)
  let pong = pongTempl.get(newStringBitStream(resp.data))

template udpTrackerPingPong(pingTempl, pongTempl: untyped) {.dirty.} =
  udpTrackerPing(pingTempl); udpTrackerPong(pongTempl)

proc udpTrackerHello(tracker: Uri): Future[(AsyncSocket, int64)] {.async.} =
  var socket = newAsyncSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
  let ping = UdpTrackerConnectPing(connection_id: 0x41727101980, action: 0, transaction_id: rand(int32))
  udpTrackerPingPong(udpTrackerConnectPing, udpTrackerConnectPong)
  result = if resp.data.len == 16 and ping.action == pong.action and ping.transaction_id == pong.transaction_id:
    (socket, pong.connection_id) else: raise newException(TimeoutError, "Udp tracker ping unsuccessful")

proc udpTrackerScrape*(infoHashes: seq[string], tracker: Uri): Future[seq[(uint32,uint32,uint32)]] {.async.} =
  var (socket, connection_id) = await udpTrackerHello(tracker)
  let ping = UdpTrackerScrapePing(connection_id: connection_id, action: 2, transaction_id: rand(int32), info_hashes: infoHashes)
  udpTrackerPingPong(udpTrackerScrapePing, udpTrackerScrapePong)
  result = if ping.action == pong.action and ping.transaction_id == pong.transaction_id:
    pong.info.mapIt((it.complete, it.downloaded, it.incomplete)) else: @[]

template udpTrackerScrape*(infoHash: string, tracker: Uri): Future[seq[(uint32,uint32,uint32)]] = #overload for a single infohash scrape
  udpTrackerScrape(@[infoHash], tracker)

proc udpTrackerAnnounce*(info_hash: string, tracker: Uri): Future[seq[PeerAddr]] {.async.} =
  var (socket, connection_id) = await udpTrackerHello(tracker) #say hello and return socket and connection id
  let ping = UdpTrackerAnnouncePing(connection_id: connection_id, action: 1, transaction_id: rand(int32), info_hash: info_hash,
    peer_id: PEER_ID, downloaded: 0, left: 0, uploaded: 0, event: 0, ip: 0, key: rand(uint32), num_want: 10000, port: port, extensions: 0)
  udpTrackerPingPong(udpTrackerAnnouncePing, udpTrackerAnnouncePong)
  result = if resp.data.len>=20 and ping.action == pong.action and ping.transaction_id == pong.transaction_id:
    pong.peerList.mapIt((ipAddress(it.ip),Port(it.port))) else: @[]

proc udpTrackerAuthPart*(username:string, password: string): string =
  var pass = password.secureHash(); var hash = newString(8)
  copyMem(hash[0].addr, pass.addr, 8)   #todo remove when nim can convert seq[byte] to string https://github.com/nim-lang/Nim/issues/14810
  let ping = UdpTrackerAuth(username_length: username.len.int8, username: username, passwd_hash: hash)
  var pingStr = newStringBitStream(); udpTrackerAuth.put(pingStr, ping); pingStr.setPosition(0)
  return pingStr.readAll()

when isMainModule:
  #echo waitFor udpTrackerScrape(@[parseHexStr("125b77979ba4b183eb702f4ff00df9ff22c452d7"), parseHexStr("20660e4c00dca794e8722d0ffec402b42094bf80")], parseUri("udp://tracker.opentrackr.org:1337/announce"))
  #echo waitFor udpTrackerAnnounce(parseHexStr("125b77979ba4b183eb702f4ff00df9ff22c452d7"), parseUri("udp://tracker.opentrackr.org:1337/announce")) 
  #echo waitFor udpTrackerAnnounce(parseHexStr("125b77979ba4b183eb702f4ff00df9ff22c452d7"), parseUri("udp://p4p.arenabg.com:1337/announce")) 
  try:
    #echo waitFor udpTrackerAnnounce(parseHexStr("125b77979ba4b183eb702f4ff00df9ff22c452d7"), parseUri("udp://9.rarbg.to:2710/announce")) 
    echo waitFor udpTrackerAnnounce(parseHexStr("125b77979ba4b183eb702f4ff00df9ff22c452d7"), parseUri("udp://p4p.arenabg.com:1337/announce"))
    #echo waitFor udpTrackerScrape(@[parseHexStr("125b77979ba4b183eb702f4ff00df9ff22c452d7")], parseUri("udp://9.rarbg.to:2710/announce")) 
    echo waitFor udpTrackerScrape(@[parseHexStr("125b77979ba4b183eb702f4ff00df9ff22c452d7"), parseHexStr("20660e4c00dca794e8722d0ffec402b42094bf80")], parseUri("udp://tracker.opentrackr.org:1337/announce")) 
    #echo waitFor udpTrackerScrape(@[parseHexStr("125b77979ba4b183eb702f4ff00df9ff22c452d7"), parseHexStr("20660e4c00dca794e8722d0ffec402b42094bf80")], parseUri("http://tracker1.itzmx.com:8080/announce")) 
  except CatchableError as e:
    echo e.name

