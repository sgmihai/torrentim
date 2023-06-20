import asyncdispatch, net, asyncnet, asyncfile, binarylang, os, terminal
import std/importutils
import std/sha1 #for check piece, maybe move somewhere else
import bitvector
import ./types
import ./globals
import ./core
import ./piece
import ./io
include protocol/peerMessageStruct

when (compiles do: import morelogging): discard # just for debug

import timeit

export types.Peer #why?

proc pChoked*(self: Peer, state: bool) = self.choking = state; echo "peer choked us = " & $state
proc pInterested*(self: Peer, state: bool) = self.interested = state; echo "peer interest in us = " & $state
proc pHave*(self: Peer, pnr:int) = echo "peer has piece " & $pnr #todo actual implementation
proc psInterested*(self: Peer, state: bool) {.async.} =
  let msgStr = int2msg(1'u32) & chr(3-ord(state))
  await self.asocket.send(msgStr)
proc psChoked*(self: Peer, state: bool) {.async.} =
   let msgStr = int2msg(1'u32) & chr(1-ord(state))
   await self.asocket.send(msgStr)

proc pReqPiece*(self: Peer, blk: BlockInfo) {.async.} = #request: <len=0013><id=6><index><begin><length>
  let reqS = int2msg(13'u32) & "\6" & int2msg(blk.pieceN.uint32) & int2msg(blk.offset.uint32) & int2msg(blk.len.uint32)
  await self.asocket.send(reqS)
 # echo "sent request for piece " & $pieceN
 # echo "request message is " & $cast[seq[uint8]](reqS) 

proc peerSayHello*(socket: AsyncSocket, info_hash: InfoHash, peer_id = PEER_ID) {.async.} =
  let ping = PeerPingMessage(pstrlen: pstrlen, pstr: pstr, protoExt: protoExt, info_hash: info_hash, peer_id: peer_id)
  var pingStr = newStringBitStream(); peerPingMessage.put(pingStr, ping); pingStr.setPosition(0)
  #echo pingStr.readAll().len; pingStr.setPosition(0); echo cast[seq[uint8]](pingStr.readAll()); pingStr.setPosition(0)
  discard await socket.send(pingStr.readAll()).withTimeout(PEER_TIMEOUT)
  #await self.asocket.send(handshake)
  #echo "sent peer hello to "

proc peerSayHello*(self: Peer, info_hash, peer_id = PEER_ID) {.async.} =
  await peerSayHello(self.asocket, info_hash, peer_id)

proc peerHearHello*(socket:  AsyncSocket, info_hash: string): Future[string] {.async.} =
  let resp = await socket.recv(68).withTimeoutEx(PEER_TIMEOUT)
  #echo resp.len; echo resp
  if resp.len == 0:
    echo "disconnected " #todo - raise exception here
    return
  let pong = peerPingMessage.get(newStringBitStream(resp))
  if info_hash == pong.info_hash:
    #self.peer_id = pong.peer_id
    #echo "we got peer_id " & pong.peer_id
    return pong.peer_id
  else: raise newException(TimeoutError, "pong info hash does not match")

proc peerHearHello*(self: Peer, info_hash: string) {.async.} =
  self.peer_id = await peerHearHello(self.asocket, info_hash)

#lower level proc definition using sock/host as parameters
proc peerConnect*(socket:  AsyncSocket, ip: IpAddress, port: Port) {.async.} =
  #echo "bullshit"
  await socket.connect(ip, port)#.withTimeoutEx(PEER_TIMEOUT) #TODO IMPORTANT WHY DID THIS BREAK

#higher level proc definition using Peer object as parameter
proc peerConnect*(self: Peer) {.async.} =
  #await self.asocket.connect($self.host.ip, self.host.port)
  await peerConnect(self.asocket, self.host.ip, self.host.port)
  #echo "connected to " & $self.host.ip & ":" & $self.host.port

#peer connect version that returns a socket, to be used for experimenting outside the Peer object that holds the socket var
proc peerConnect*(ip: IpAddress, port: Port): Future[AsyncSocket] {.async.} =
  var socket = newAsyncSocket()
  #try:
  #  discard await socket.connect($ip, port).withTimeout(PEER_TIMEOUT)#.withTimeoutEx(PEER_TIMEOUT) why doesn't this work ? something to do with void return type?
  await peerConnect(socket, ip, port)
  #except: echo "exception"
  return socket

proc peerProcessBlock*(self: Peer, t: Torrent, msg: PeerMessage, chunk:string) {.async.} =

  await writeBlock((msg.payl.indexP.uint, msg.payl.beginP.uint, chunk.len.uint), chunk, t)

  #writeFile("test/chunks/" & $msg.payl.indexP & " " & $msg.payl.beginP & " " & $msg.payl.chunk.len & ".block", $msg.len & $msg.id & $msg.payl.indexP & $msg.payl.beginP & msg.payl.chunk)
  #var file: AsyncFile
  #let fileName = "test/chunks/file.bin"
  #  var file = openAsync(getTempDir() / "foobar.txt", fmReadWrite)
 #[ if not fileExists(fileName):
    writeFile(fileName, "")
    var file = openAsync(fileName, fmReadWriteExisting)
    #await file.write("")
    file.setFilePos(t.size.int64 - 1)
    await file.write("\0")
    file.close()
  
  if fileExists(fileName):
    var file = openAsync(fileName, fmReadWriteExisting)
    let offset = msg.payl.indexP.uint * t.pieceSize + msg.payl.beginP.uint
    file.setFilePos(offset.int64)
    await file.write(chunk)
    file.close()]#

proc initBitField(aPeer: Peer, bitField: string) =
  privateAccess(BitVector)
  aPeer.bitField = newBitVector[uint](bitField.len*8)
  copyMem(aPeer.bitField.Base[0].addr, bitField[0].unsafeAddr, bitField.len)

proc setBitInField(bitField: var BitVector, n: int, value = 1) =
  bitField[n] = value

func hasWantedPieces(peer, want, have: BitVector): bool =
  if peer.len != want.len: return false
  for i in 0..want.len - 1:
    if want[i].bool: (if not have[i].bool: (if peer[i].bool: return true)) #if we actually want to download that piece and don't already have it, and if remote peer has it
  return false

func hasWantedPieces(peer: Peer, t: Torrent): bool =
  return hasWantedPieces(peer.bitField, t.pcsWant, t.pcsHave)

proc sendBlock(peer: Peer, t: Torrent, blk: BlockInfo) =
  if isValidBlockRange(t.pieceSize, t.numPieces, blk):
    #if t.blkHave[blk.p].bool:
    
      discard
    #let piece 
  #get data, with exception
  #send piece

proc hasPiece(p: Peer, pieceIdx: PieceNum): bool = #TODO turn this into a template
  return p.bitField[pieceIdx.int].bool

func isBitFieldAll1s(x: BitVector): bool = #TODO rewrite so that is compares chunks of Base instead of individual bits, for speed
  for i in 0..x.len-1:
    if x[i] == 0: return false
  return true

template isLeech(p: Peer): bool =
  not p.bitField.isBitFieldAll1s()

template isSeed(p: Peer): bool =
  p.bitField.isBitFieldAll1s()

func howManyBitsInField(x: BitVector, bit:int = 1): int =
  for i in 0 .. x.len-1:
    if x[i] == bit:
      inc result

template peerHello(peer: Peer, infohash: InfoHash) =
  try:
    await peerConnect(peer)
    await peerSayHello(peer, infohash, PEER_ID)
    await peerHearHello(peer, infohash)
  except: echo "we got an exception establishing peer connection: "

proc peerLoop*(peer: Peer, t: Torrent) {.async.} =
  echo peer.host.ip
  peerHello(peer, t.sha1)
  #await psChoked(peer, false)
  #while true:
  #  if peer.hasWantedPieces(t): await psInterested(peer, true); break
   # else: await sleepAsync(10000)
    
  #warning, this loop logic won't work if peer doesn't send us bitfield msg after handshake, which is optional (probably not so in practice unless peer has no pieces to begin with)
  peer.maxRequests = 1
  peer.bitField = newBitVector[uint](t.numPieces.int) #avoid errors in case we don't have bitfield received/initialized
  var whatmax = 0
  while true:
    var msgSize = await peer.asocket.recv(4)
    case msg2int(msgSize):
      of 0: continue  #keep-alive: <len=0000>
      of -1: echo "disconnected"; break
      else: discard
    #echo msgSize; echo msgSize.len; echo msg2int(msgSize);
    var resp: string
    try:
      resp = await peer.asocket.recv(msg2Int(msgSize))#.withTimeoutEx(PEER_TIMEOUT) #add 4 to get the full message payload, including 4byte msgSize we peeked
    except CatchableError as e: echo "we got an exception getting the peer message"
    #echo resp
    #writeFile($resp[5..8].msg2Int & $resp[9..12].msg2Int&".pkt", resp[13..^1])
    var bistr = newStringBitStream(msgSize & resp)
    #echo "all data that would have been passed to parser is len: " & $alldata.len
    let peerMsg = peerMessage.get(bistr)
    let msgLen = peerMsg.len
    let msgType = peerMsg.id#reply[0].uint8
    case msgType: #todo - look into "define a sequence of procs in an array, and call the one with the index of msgType directly; so that I can do, on msgReceive: msgHandle[msgType]
      of 0: pChoked(peer, true) #choke: <len=0001><id=0>
      of 1: pChoked(peer, false)#unchoke: <len=0001><id=1> ; await psChoked(aPeer, false); await psInterested(aPeer, true)
      of 2: pInterested(peer, true) #interested: <len=0001><id=2>
      of 3: pInterested(peer, false) #not interested: <len=0001><id=3>
      of 4:
        echo "debug pieceIndex for havePiece msg " & peer.peer_id & " " & $peerMsg.payl.pieceIndex & " len of bitfield " & $peer.bitField.len
        setBitInField(peer.bitField, peerMsg.payl.pieceIndex) #have: <len=0005><id=4><piece index>
      of 5:
        initBitField(peer, peerMsg.payl.bitField)
        echo "debug bitfield len " & $peer.bitfield.len & " has 0s " & $howManyBitsInField(peer.bitfield,0) #bitfield: <len=0001+X><id=5><bitfield>
      of 6: sendBlock(peer, t, (pieceN: peerMsg.payl.indexR.uint, offset:peerMsg.payl.beginR.uint, len:peerMsg.payl.lengthR.uint)) #request: <len=0013><id=6><index><begin><length>
      of 7:
        dec peer.requests; await peerProcessBlock(peer, t, peerMsg, resp[9..^1]) #piece: <len=0009+X><id=7><index><begin><block>  #debug for writing wire packets to disk: writeFile(absolutePath("./test/pkts/") & $(resp[1..4].msg2Int) & $(resp[5..8].msg2Int)&".pkt", resp[9..^1])
      of 8: echo "we got a cancel" #cancel: <len=0013><id=8><index><begin><length>
      of 9: echo "port" #port: <len=0003><id=9><listen-port>
      else: discard
    if not peer.choking:
      if peer.isSeed: #only download from seeds until logic is fixed
        let blkInfo = t.blkRequester()
        if (blkInfo.len > 0) and (peer.requests < peer.maxRequests): #and peer.hasPiece(blkInfo.PieceNum)
          discard #t.blkActive[] #todo: iterator could return block index instead of recalculatig it here
          inc peer.requests
          if (peer.requests > whatmax): (whatmax = peer.requests)
          asyncCheck pReqPiece(peer, blkInfo)
        else: await sleepAsync(0)
  echo peer.peer_id & " " & $whatmax
      #pcNum * pcsize blkid
