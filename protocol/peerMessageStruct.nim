import binarylang
from binarylang/operations import condGet, condPut
#import binarylang/plugins

type
  MsgType* = enum
    mChoke = 0
    mUnchoke = 1
    mInterested = 2
    mNotInterested = 3
    mHave = 4
    mBitfield = 5
    mRequest = 6
    mPiece = 7
    mCancel = 8
    mPort = 9

#template byteSeqToStrGet*(parse, parsed, output, len: untyped): string =
#  parse
#  output = cast[string](output[0])

union(payload, MsgType, len:int):
  (mChoke):
    nil 
  (mUnchoke):
    nil 
  (mInterested):
    nil
  (mNotInterested):
    nil
  (mHave):
    32: pieceIndex
  (mBitfield):
    s: bitField(len)
  (mRequest):
    32: indexR
    32: beginR
    32: lengthR
  (mPiece):
    32: indexP
    32: beginP
    s:  chunk(len-9)
    #8 {byteSeqToStr(len-9)}: chunk[16384]
  (mCancel):
    32: indexC
    32: beginC
    32: lengthC
  (mPort):
    16: port

struct(peerMessage, endian = b):
  32: len
  8 {cond(len>0)}: id
  +payload(MsgType(id), len) : payl(len-1) #{cond(len > 0 and id in (0..9))}

struct(peerPingMessage):
  8: pstrlen = 19
  s: pstr(pstrlen) = "BitTorrent protocol"
  s: protoExt(8)
  s: info_hash(20)
  s: peer_id(20)