#specification: https://www.libtorrent.org/udp_tracker_protocol.html
#todo implement handling optional error messages (if action = 3: goto error body)
import binarylang, random

#udp tracker connect messages
struct(udpTrackerConnectPing, endian = b, visibility = public):
  64: connection_id = 0x41727101980
  32: action = 0
  32: transaction_id = rand(int32)

struct(udpTrackerConnectPong, endian = b):
  32: action
  32: transaction_id
  64: connection_id

#udp tracker scrape messages
struct(udpTrackerScrapePing, endian = b):
  64: connection_id = connection_id
  32: action = 2
  32: transaction_id = rand(int32)
  s:  info_hashes(20){s.atEnd}

struct(udpTrackerScrapePongInfo, endian = b):
  u32: complete
  u32: downloaded
  u32: incomplete

struct(udpTrackerScrapePong, endian = b):
  32: action
  32: transaction_id
  *udpTrackerScrapePongInfo: info{s.atEnd} #todo check if trackers actually support multi infohash scrape and maybe use that as size?

#udp tracker announce messages
struct(udpTrackerAnnouncePing, endian = b):
  64: connection_id = connection_id
  32: action = 1
  32: transaction_id = rand(int32)
  s: info_hash(20)
  s: peer_id(20)
  64: downloaded
  64: left
  64: uploaded
  32: event
  lu32: ip = 0 #ip is little endian
  u32: key = rand(uint32)
  32: num_want = 10000
  u16: port = port
  u16: extensions = 0

struct(udpTrackerAnnouncePongPeer, endian = b):
  l32: ip
  u16: port

struct(udpTrackerAnnouncePongPeerList,  visibility = public):#, endian = b):
  *udpTrackerAnnouncePongPeer: peerList{s.atEnd}

struct(udpTrackerAnnouncePong, endian = b):
  32: action
  32: transaction_id
  32: repInterval
  32: leechers
  32: seeders
  *udpTrackerAnnouncePongPeer: peerList{s.atEnd}# [leechers+seeders]

#udp tracker authentification message
struct(udpTrackerAuth, endian = b):
  8: username_length
  s: username(username_length)
  s: passwd_hash(8)