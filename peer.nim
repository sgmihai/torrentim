#WIP, not functional
import asyncdispatch, net, asyncnet, asyncfile, binarylang, os, terminal
import bitvector
import ./types
import ./globals
import ./core
include protocol/peerMessageStruct

import timeit

export types.Peer

proc pChoked*(self: Peer, state: bool) = self.choking = state; echo "peer choked us = " & $state
proc pInterested*(self: Peer, state: bool) = self.interested = state; echo "peer interest in us = " & $state
proc pHave*(self: Peer, pnr:int) = echo "peer has piece " & $pnr #todo actual implementation
proc psInterested*(self: Peer, state: bool) {.async.} =
  let msgStr = int2msg(1'u32) & chr(3-ord(state))
  await self.asocket.send(msgStr)
proc psChoked*(self: Peer, state: bool) {.async.} =
   let msgStr = int2msg(1'u32) & chr(1-ord(state))
   await self.asocket.send(msgStr)
   echo "sent message choke = " & $state
   echo "choke message is " & $cast[seq[uint8]](msgStr) 

proc pReqPiece*(self: Peer, pieceN, offset, pieceLen: uint) {.async.} = #request: <len=0013><id=6><index><begin><length>
  let reqS = int2msg(13'u32) & "\6" & int2msg(pieceN) & int2msg(offset) & int2msg(pieceLen)
  await self.asocket.send(reqS)
  echo "sent request for piece " & $pieceN
  echo "request message is " & $cast[seq[uint8]](reqS) 

proc peerSayHello*(socket:  AsyncSocket, info_hash, peer_id = PEER_ID) {.async.} =
  let ping = PeerPingMessage(pstrlen: pstrlen, pstr: pstr, protoExt: protoExt, info_hash: info_hash, peer_id: peer_id)
  var pingStr = newStringBitStream(); peerPingMessage.put(pingStr, ping); pingStr.setPosition(0)
  #echo pingStr.readAll().len; pingStr.setPosition(0); echo cast[seq[uint8]](pingStr.readAll()); pingStr.setPosition(0)
  discard await socket.send(pingStr.readAll()).withTimeout(PEER_TIMEOUT)
  #await self.asocket.send(handshake)
  echo "sent handshake"

proc peerSayHello*(self: Peer, info_hash, peer_id = PEER_ID) {.async.} =
  await peerSayHello(self.asocket, info_hash, peer_id)

proc peerHearHello*(socket:  AsyncSocket, info_hash: string): Future[string] {.async.} =
  let resp = await socket.recv(68).withTimeoutEx(PEER_TIMEOUT)
  echo resp.len; echo resp
  if resp.len == 0:
    echo "disconnected " #todo - raise exception here
    return
  let pong = peerPingMessage.get(newStringBitStream(resp))
  if info_hash == pong.info_hash:
    #self.peer_id = pong.peer_id
    echo "we got peer_id " & pong.peer_id
    return pong.peer_id
  else: raise newException(TimeoutError, "pong info hash does not match")

proc peerHearHello*(self: Peer, info_hash: string) {.async.} =
  self.peer_id = await peerHearHello(self.asocket, info_hash)

#lower level proc definition using sock/host as parameters
proc peerConnect*(socket:  AsyncSocket, ip: IpAddress, port: Port) {.async.} =
  await socket.connect($ip, port).withTimeoutEx(PEER_TIMEOUT)

#higher level proc definition using Peer object as parameter
proc peerConnect*(self: Peer) {.async.} =
  #await self.asocket.connect($self.host.ip, self.host.port)
  await peerConnect(self.asocket, self.host.ip, self.host.port)
  echo "connected to " & $self.host.ip & ":" & $self.host.port

proc peerConnect*(ip: IpAddress, port: Port): Future[AsyncSocket] {.async.} =
  var socket = newAsyncSocket()
  discard await socket.connect($ip, port).withTimeout(PEER_TIMEOUT)#.withTimeoutEx(PEER_TIMEOUT)
  return socket

proc peerProcessPiece*(self: Peer, t: Torrent, msg: PeerMessage ) {.async.} =
   #need to write it here
  #msg.payl.indexP
  #msg.payl.beginP

  echo "we are in the process piece proc"
  echo msg.payl.chunk
  #let index = msg2Int(reply[1..4])
  #let offset = msg2Int(reply[5..8])
  #let subpiece = reply[9..^1]
  #echo "length of subpiece we got is " & $subpiece.len
  #await file.write("test")
  #file.setFilePos(0)
  #let data = await file.readAll()
  #doAssert data == "test"
  #file.close()
  #echo "getting piece " & $msg2int(reply[1..4])

#hack - BitVector.Base is not exported, I modified the file manually to export it. See if there is any workaround to this.
proc initBitField(aPeer: Peer, bitField: string) =
  aPeer.bitField = newBitVector[uint](bitField.len*8)
  copyMem(aPeer.bitField.Base[0].addr, bitField[0].unsafeAddr, bitField.len)

proc setBitInField(bitField: var BitVector, n: int, value = 1) =
  bitField[n] = value

func isValidBlockRange(pSize, numPieces:uint, pNum, bOffset, bLen: int): bool =
  pNum in (0..numPieces.int) and bOffset+bLen <= pSize.int

proc sendPiece(peer: Peer, t: Torrent, pNum, bOffset, bLen: int) =
  if isValidBlockRange(t.pieceSize, t.numPieces, pNum, bOffset, bLen):
    if t.pcsHave[pNum].bool:
    
      discard
    #let piece 
  #get data, with exception
  #send piece

func block2piece(blkNum, pieceSize, numBlocks, max_block_size, size: uint): tuple[pieceN: uint, offset: uint, length:uint] =
  return ((blkNum*max_block_size div pieceSize).uint, (blkNum*max_block_size mod pieceSize).uint, if blkNum != numBlocks-1: max_block_size.uint else: (size mod max_block_size).uint)

proc blockDispatcher*(t: Torrent): tuple[pieceN: uint, offset: uint, length:uint] =
  echo "in block dispatch we have numBlocks " & $t.numBlocks
  var m = monit("first"); m.start()
  for i in 0..t.numBlocks-12:
    if t.blkHave[i.int] == 0 and t.blkWant[i.int] == 1 and t.blkActive[i.int] == 0:
      echo "step 1"
      #if i != t.numBlocks-1:
      t.blkActive[i.int] = 1
      m.finish()
      return block2piece(i.uint, t.pieceSize, t.numBlocks, max_block_size.uint, t.size)
     #   return ((i*max_block_size div t.pieceSize).uint, (i*max_block_size mod t.pieceSize).uint, max_block_size.uint)
     # else: return ((i*max_block_size div t.pieceSize).uint, (i*max_block_size mod t.pieceSize).uint, (t.size mod max_block_size).uint)

proc peerLoop*(peer: Peer, t: Torrent) {.async.} =
  echo peer.host.ip
  try:
    await peerConnect(peer)
    await peerSayHello(peer, t.sha1, PEER_ID)
    await peerHearHello(peer, t.sha1)
  except CatchableError as e: echo "we got an exception establishing peer connection"
  #await psChoked(peer, false)
  await psInterested(peer, true)
  var file = openAsync(getTempDir() / "foobar.txt", fmReadWrite)
  while true:
    echo "begin"
   # var msgSize = ""
    var msgSize = await peer.asocket.recv(4)
    case msg2int(msgSize):
      of 0: echo "got keepalive"; continue
      of -1: echo "disconnected"; break
      else: discard
    echo msgSize; echo msgSize.len; echo msg2int(msgSize);
    var resp: string
    try:
      resp = await peer.asocket.recv(msg2Int(msgSize)).withTimeoutEx(TRACKER_TIMEOUT+1000) #add 4 to get the full message payload, including 4byte msgSize we peeked
    except CatchableError as e: echo "we got an exception getting the peer message"
    echo resp
    echo resp.len
    let peerMsg = peerMessage.get(newStringBitStream(msgSize & resp))
    #echo "len " & $(peerMsg.len)
    #echo "id " & $peerMsg.id
    #echo ""
    let msgLen = peerMsg.len
    #echo "msg len in struct is " & $peerMsg.len
    #let msgLen = msg2int(await aPeer.asocket.recv(4))    if msgLen == -1: echo "peer disconnected"; return #if msglen is -1 then the received string from the socket is empty, which means disconnect
    #echo "got a message of length " & $msgLen

    #let reply = resp
    let msgType = peerMsg.id#reply[0].uint8
    echo msgType
    #echo reply
    case msgType: #todo - look into "define a sequence of procs in an array, and call the one with the index of msgType directly; so that I can do, on msgReceive: msgHandle[msgType]
      of 0: pChoked(peer, true)
      of 1: pChoked(peer, false)#; await psChoked(aPeer, false); await psInterested(aPeer, true)
      of 2: pInterested(peer, true)
      of 3: pInterested(peer, false)
      of 4: setBitInField(peer.bitField, peerMsg.payl.pieceIndex)
      of 5: initBitField(peer, peerMsg.payl.bitField)
      of 6: sendPiece(peer, t, peerMsg.payl.indexR, peerMsg.payl.beginR, peerMsg.payl.lengthR)
      of 7: await peerProcessPiece(peer, t, peerMsg)
      of 8: echo "we got a cancel"
      of 9: echo "port"
      else:
        discard
    if not peer.choking:
      let (a,b,c) = blockDispatcher(t)
      echo "we got a b c (piece offset len) for " & $peer.host & " " & $a & " " & $b & " " & $c
      #let x = readLine(stdin)
      await sleepAsync(200)
      await pReqPiece(peer, a, b, c)
    #let c = getch()
    #case c:
    #of '3': max_subpiece_size = 32768
    #of '1': max_subpiece_size = 16384
    #else: discard
