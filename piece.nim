import std/[sha1, os, sequtils, paths]
import bitvector
import ./types
import ./globals
#import ./io

#get block request -> sendBlock.block2Data(piece, t) -> fileSlices2bytes (block2FileSlices, relPaths2Absolute(slices filesmapped to paths))
#get block message -> writeBlock(blockInfo, blockData) -> block2FileSlices

#await peerProcessBlock(t, peerMsg, resp[9..^1]) 
#await peerProcessBlock( (msg.payl.indexP, msg.payl.beginP, msg.payl.chunk.len), msg.payl.chunk)

#converts a raw block index (considering all the torrent is made of blocks) into BlockInfo (pieceIdx, offset, len)


func blockInfo2Range(blk: BlockInfo, pieceSize: uint): BlockRange =
  let iPos = blk.pieceN * pieceSize + blk.offset
  let ePos = iPos + blk.len
  return (iPos, ePos)

func blkNum2BlockInfo*(blkNum, pieceSize, numBlocks, max_block_size, size: uint): BlockInfo =
  ((blkNum*max_block_size div pieceSize).uint,
   (blkNum*max_block_size mod pieceSize).uint,
   if blkNum != numBlocks-1: max_block_size.uint else: (size - blkNum*max_block_size).uint)

proc dispatchClosure*(t:Torrent): BlockRequester =
  iterator dispatch(): BlockInfo {.closure.} =
    for i in 0..(t.numBlocks-1).int:
      if t.blkHave[i] == 0 and t.blkWant[i] == 1 and t.blkActive[i] == 0:
        t.blkActive[i] = 1
        yield blkNum2BlockInfo(i.uint, t.pieceSize, t.numBlocks, max_block_size.uint, t.size)
  result = dispatch

func checkPiece(t:Torrent, x: PieceNum, correctSha: SecureHash): bool =
  discard

func checkPiece(ourSHA, correctSHA: SecureHash): bool =
  discard

func isValidBlockRange*(pSize, numPieces:uint, blk: BlockInfo): bool =
  blk.pieceN.int in (0..numPieces.int) and (blk.offset + blk.len <= pSize.uint)

proc block2FileSlices*(blkRange: BlockRange, files:seq[TorrentFile]): seq[FileSlice] =
  for i, file in files:
    let fileStart = file.offset
    let fileEnd = fileStart + file.size

    let overlapStart = max(blkRange.blkStartPos, fileStart)
    let overlapEnd = min(blkRange.blkEndPos, fileEnd)
    let overlapLen = overlapEnd.int - overlapStart.int

    if overlapLen <= 0:
      continue
    
    let fileOffset = overlapStart - fileStart
    result.add((i.uint, fileOffset, overlapLen.uint))

proc block2FileSlices*(blk: BlockInfo, t: Torrent): seq[FileSlice] =
  let blkRange = blockInfo2Range(blk, t.pieceSize)
  assert (blkRange.blkStartPos >= 0) and (blkRange.blkEndPos <= t.size) 
  block2FileSlices(blkRange, t.files)

#TODO
#binary search from chat gpt
#[files = sorted(get_files(), key=lambda x: x.get_start_offset())

# Use binary search to find the first file that overlaps with the requested block
low = 0
high = len(files) - 1
while low <= high:
    mid = (low + high) // 2
    file = files[mid]
    file_start_offset = file.get_start_offset()
    file_end_offset = file_start_offset + file.get_length()

    if file_end_offset < block_start_offset:
        low = mid + 1
    elif file_start_offset > block_end_offset:
        high = mid - 1
    else:
        # We found a file that overlaps with the requested block
        break
else:
    # No files overlap with the requested block, so return empty lists
    return file_offsets, file_lengths

# Loop through the files that overlap with the requested block
while mid < len(files):
    file = files[mid]
    file_start_offset = file.get_start_offset()
    file_end_offset = file_start_offset + file.get_length()

    # Determine the overlap between the requested block and the file
    overlap_start = max(block_start_offset, file_start_offset)
    overlap_end = min(block_end_offset, file_end_offset)
    overlap_length = overlap_end - overlap_start

    # If there is no overlap, move on to the next file
    if overlap_length <= 0:
        break

    # Calculate the offset within the file for the start of the overlap
    file_offset = overlap_start - file_start_offset

    # Add the file offset and length to the list
    file_offsets.append(file_offset)
    file_lengths.append(overlap_length)

    mid += 1

# Return the file offsets and lengths
return file_offsets, file_lengths]#



#[
proc peerProcessBlock*(self: Peer, t: Torrent, msg: PeerMessage, chunk:string) {.async.} =
  #writeFile("test/chunks/" & $msg.payl.indexP & " " & $msg.payl.beginP & " " & $msg.payl.chunk.len & ".block", $msg.len & $msg.id & $msg.payl.indexP & $msg.payl.beginP & msg.payl.chunk)
  #var file: AsyncFile
  let fileName = "test/chunks/file.bin"
  #  var file = openAsync(getTempDir() / "foobar.txt", fmReadWrite)
  if not fileExists(fileName):
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