import udp_tracker2, peer
import net, asyncnet, asyncdispatch, strutils, uri
import ./globals

let peers = waitFor udpTrackerAnnounce(parseHexStr("125b77979ba4b183eb702f4ff00df9ff22c452d7"), parseUri("udp://p4p.arenabg.com:1337/announce"))
let info_hash = "125b77979ba4b183eb702f4ff00df9ff22c452d7"

#ip, port, infohash
proc peerHasTorrent(ip: IpAddress, port: Port, info_hash: string): Future[int] {.async.} =
  try:
    var socket = await peerConnect(ip, port)
    echo "before hello"
    await peerSayHello(socket, info_hash, PEER_ID)
    echo "after hello"
    result = (await peerHearHello(socket, info_hash)).len
    echo "we return " & $result 
  except: discard

echo peers
var futs: seq[Future[int]]
for peer in peers:
  echo "ip " & $peer.ip & " port " & $peer.port
  #if not ($peer.ip).startsWith("193"):
  #futs.add(peerHasTorrent(peer.ip, peer.port, info_hash))
  #echo waitFor peerHasTorrent(peer.ip, peer.port, info_hash)
  #let x = readline(stdin)

#discard waitFor all futs
#for fut in futs:
#  echo fut.read
waitFor peerHasTorrent("198.98.49.103", peer.port, info_hash)
