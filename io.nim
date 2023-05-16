import std/[asyncdispatch, asyncfile, os, sequtils, streams, paths, files] #files for fileExists
import ./types
import ./piece
import bitvector

template writeFileForced(file: Path) =
  discard existsOrCreateDir(file.parentDir.string)
  writeFile(file.string, "")

func relPaths2Absolute*(paths: seq[Path], basePath: Path): seq[Path] =
  result = paths.mapIt(it.absolutePath(basePath))

proc makeEmptyFiles*(files: seq[TorrentFile], basePath: Path) {.async.} =
  for tFile in files:
    let filePath = tFile.path.absolutePath(basePath)
    if not filePath.fileExists():
      writeFileForced(filePath)
      var file = openAsync(filePath.string, fmReadWriteExisting)
      file.setFilePos(tFile.size.int64 - 1)
      await file.write("\0")
      file.close()

proc makeEmptyFiles*(t: Torrent) {.async.} =
  await makeEmptyFiles(t.files.pairs().toSeq.filterIt(t.filesWanted[it[0]] == 1).unzip()[1], t.basePath)

func getAbsPaths(t: Torrent): seq[Path] =
  discard

proc readBlock*(files: seq[FileSlice], paths: seq[Path]): string  =
  assert files.len == paths.len
  var buf: string
  for idx in 0..files.len-1:
    if fileExists(paths[idx]):
      var strm = newFileStream(paths[idx].string, fmRead) #todo check if they will update the proc to take Path instead of string
     # var file = openAsync(fileName, fmRead)
      #file.setFilePos(files[idx].offset)
      strm.setPosition(files[idx].offset.int)
      result.add(strm.readStr(files[idx].len.int))
      close(strm)

proc readBlock*(blk: BlockInfo, t: Torrent): string =
  let slices = block2FileSlices(blk, t)
  let paths = relPaths2Absolute(slices.mapIt(it.fileN).mapIt(t.files[it].path), t.basePath)
  return readBlock(slices, paths)


proc writeDataToFile(offset, len: uint, data: string, filePath: Path) {.async.} =
  var file = openAsync(filePath.string, fmReadWriteExisting) #todo check if they will update the proc to take Path instead of string
  file.setFilePos(offset.int64)
  await file.write(data)
  file.close()

proc writeBlock*(blk: BlockInfo, blkData: string, files: seq[TorrentFile], slices: seq[FileSlice], paths: seq[Path]) {.async.} =
  var p: uint = 0
  for i, slice in slices:
    await writeDataToFile(slice.offset, slice.len, blkData[p..p + slice.len - 1], paths[i])
    p = p + slice.len

proc writeBlock*(blk: BlockInfo, blkData: string, t: Torrent) {.async.} =
  let slices = block2FileSlices(blk, t)
  let paths = relPaths2Absolute(slices.mapIt(it.fileN).mapIt(t.files[it].path), t.basePath)
  await writeBlock(blk, blkData, t.files, slices, paths)

