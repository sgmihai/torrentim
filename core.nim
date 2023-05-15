import std/endians, sequtils
import std/asyncdispatch, std/httpclient, std/net
import ./types
import binarylang
#from binarylang/operations import condGet, condPut, validGet, validPut
include protocol/udpTrackerStruct
#todo make generic de/serializer procs

proc withTimeoutEx*[T](fut: Future[T], reqTimeout:int): owned(Future[T]) {.async.} =
  let res = await fut.withTimeout(reqTimeout)
  if res: return fut.read()
  else: raise newException(TimeoutError, "Request timeout")

proc getMyIp*(): Future[string] {.async.} = 
  const myIpUrls = ["ipecho.net/plain","ipinfo.io/ip","api.ipify.org","ifconfig.me","icanhazip.com"]
  return await newAsyncHttpClient().getContent("https://" & myIpUrls[0])

proc ipAddress*(a: int32): IpAddress = ## Creates IPv4 address from 32-bit integer.
  var ip: array[0..3, uint8]
  copyMem(addr ip, a.unsafeAddr, 4)
  result = IpAddress(family: IpAddressFamily.IPv4, address_v4: ip)
#func msg2byteGeneric*[T](s: string): T =
#  case s.len:
#    of 2: swapEndian16(addr result, unsafeaddr s[0])
#    of 4: swapEndian32(addr result, unsafeaddr s[0])
#    of 8: swapEndian64(addr result, unsafeaddr s[0])
#    else: discard

#func msg2byte*(s: string): uint16 =
#  if s != "":
#    swapEndian16(addr result, unsafeaddr s[0])
#  else: discard

func msg2Int*(s: string, a:char): int64 =
  if s != "":
    swapEndian64(addr result, unsafeaddr s[0])
  else: result = -1

func msg2Int*(s: string): int =
  if s != "":
    swapEndian32(addr result, unsafeaddr s[0])
  else: result = -1

#func msg2bytes*(s:string):array[0..3, uint8] =
#  if s != "":
#    swapEndian32(addr result, unsafeaddr s[0])
#  else: discard

proc int2Msg*[T](i: T): string =
  result = newString(sizeof(i))
  case sizeof(i):
    of 2: swapEndian16(addr result[0], unsafeaddr i)
    of 4: swapEndian32(addr result[0], unsafeaddr i)
    of 8: swapEndian64(addr result[0], unsafeaddr i)
    else: discard


#proc parseBinPeerList*(x: string): seq[PeerAddr] =
#  echo "started bin peer parse"
#  var ip: array[0..3, uint8]
#  for p in countup(0,x.len-1,6):
#    copyMem(ip.addr, x[p].unsafeAddr, 4)
#    result.add (IpAddress(family: IpAddressFamily.IPv4, address_v4: ip), Port(msg2byte(x[p+4..p+5])))

proc parseBinlangPeerList*(x: string): seq[PeerAddr] =
  #var bitStr = newStringBitStream(x)
  echo "length of binlang peerlist is " & $x.len
  let peerBList = udpTrackerAnnouncePongPeerList.get(newStringBitStream(x))
  return peerBList.peerList.mapIt((ipAddress(it.ip),Port(it.port)))