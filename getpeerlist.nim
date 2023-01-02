proc getPeerList*(trackerReqUrls: seq[Uri], info_hash: string, timeout = TRACKER_TIMEOUT): Future[seq[PeerAddr]] {.async.} =
  var futs: seq[Future[seq[PeerAddr]]]
  for tracker in trackerReqUrls:
    if tracker.scheme.startsWith("http"):
      futs.add(httpTrackerAnnounce(info_hash, tracker))
    elif tracker.scheme.startsWith("udp"):
      futs.add(udpTrackerAnnounce(info_hash, tracker))
  for i, f in futs:
    try:
      result &= await f
    except CatchableError as e:
       echo "we got an exception at fut " & $i & " " & $e.name & $e.msg
    result = result.deduplicate()
