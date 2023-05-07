import net, uri, asyncnet
import comptest
import bitvector

import std/sha1
import bencode
#type btClient = enum
#  aTorrentAndroid   = "7T"
type PeerAddr* = tuple[ip: IpAddress, port: Port]
#type TFiles* = object #temp experiment, remove
#  name*: seq[string]
#  path*: DictComp[seq[string]]
#  size*: seq[uint]

#type PeerIdData = object
#  client:

type InfoHash* = array[20, char]

type PieceNum* = uint
type BlockReqInfo* = tuple[pieceN: uint, offset: uint, len:uint]
type BlockRequester* = iterator (): BlockReqInfo {.closure.}

type BencFields* = seq[(string, BencodeObj)]

type Peer* = ref object
  host*: PeerAddr
  state: char
  asocket*: AsyncSocket
  socket: Socket
  choking*, interested*, amChoking*, amInterested*: bool
  peer_id*: string
  bitField*: BitVector[uint]

type TorrentFile* = ref object
  path*: string
  offset*, size*: uint

type Torrent* = ref object
  #parts from .torrent metadata
  name*: string
  trackers*, webSeedUrls*: seq[Uri]
  private*: int
  pieceSize*: uint
  createdBy*, comment*, source*:string #and encoding?
  createdOn*: uint64
  files*: seq[TorrentFile]
  pcsHashes*: seq[string]

  sourceUri*: Uri
  sha1*: InfoHash
  sha1hex*: string #sha1
  rootPath: string
  trackerReqURLs*: seq[Uri] #still needed?
  size*, numFiles*, numPieces*, numBlocks*: uint

  #files*: TFiles
  #dirPaths: seq[seq[string]]
  #uniqPaths: seq[seq[uint32]]
  #paths*: DictComp[seq[string]]
  #filePaths*: seq[string] #temp

  handshake*: string
  paused*: bool

  peerList*: seq[PeerAddr]
  aPeer*: Peer
  conns*: seq[Peer]
  pcsHave*, pcsWant*, pcsActive*, blkHave*, blkWant*, blkActive*: BitVector[uint]

  optFields*, optInfoFields*: BencFields
  blkRequester*: BlockRequester


type httpAnnounceParams* = seq[(string,string)]
type btClientProfile = object
  httpParams: httpAnnounceParams
  peer_id: string
  ext: byte

converter ip2string*(ip: IpAddress): string = $ip

converter infoHash2str*(x: InfoHash): string = 
  var result = newString(x.len)
  copyMem(result[0].addr, x[0].unsafeAddr, x.len)
  result


converter str2InfoHash*(x: string): InfoHash =
  var result: InfoHash
  copyMem(result[0].addr, x[0].unsafeAddr, x.len)
  result

converter seqUri2SeqStr*(x: seq[Uri]): seq[string] = 
  for uri in x: result.add($uri)

converter secureHash2InfoHash*(x: SecureHash): InfoHash =
  return cast[InfoHash](x)

converter blkInfo2PieceNum*(x: BlockReqInfo): PieceNum =
  return x.pieceN