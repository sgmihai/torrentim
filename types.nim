import net, uri, asyncnet
import comptest
import bitvector

#type btClient = enum
#  aTorrentAndroid   = "7T"
type PeerAddr* = tuple[ip: IpAddress, port: Port]
#type TFiles* = object #temp experiment, remove
#  name*: seq[string]
#  path*: DictComp[seq[string]]
#  size*: seq[uint]

#type PeerIdData = object
#  client:
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

type Torrent* = ref object #of RootObj
  name*, rootPath: string
  sha1*, sha1hex*: string
  sourceUri*: Uri
  trackers*, trackerReqURLs*, urls*: seq[Uri]
  private*: bool
  pieceSize*, size*, numFiles*, numPieces*, numBlocks*: uint
  #files*: TFiles
  dirPaths: seq[seq[string]]
  uniqPaths: seq[seq[uint32]]
  files*: seq[TorrentFile]
  #paths*: DictComp[seq[string]]
  #filePaths*: seq[string] #temp
  peerList*: seq[PeerAddr]
  aPeer*: Peer
  conns*: seq[Peer]
  createdBy*, comment*, source*:string #and encoding?
  createdOn*: uint64
  handshake*: string
  paused*: bool
  pcsHashes*: seq[string]
  pcsHave*, pcsWant*, pcsActive*, blkHave*, blkWant*, blkActive*: BitVector[uint]


type httpAnnounceParams* = seq[(string,string)]
type btClientProfile = object
  httpParams: httpAnnounceParams
  peer_id: string
  ext: byte