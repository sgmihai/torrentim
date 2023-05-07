import sequtils
type DictComp*[T] = object
  data*: seq[T]
  idx*: seq[uint32]
  len*: uint32

converter toSeq*[T](d: DictComp[T]): seq[T] =
  for i in low(d.idx)..high(d.idx):
    result.add(d[i])

proc addDedupToSeq*[T](a: var seq[T], b: T): uint32 =
  let pos = a.find(b)
  if pos > -1:
    return pos.uint32
  else:
    a.add(b)
    return a.high.uint32

proc comprSeq*[T](d: var DictComp, data: seq[T]) =
  for i in low(data)..high(data):
    d.idx.add(addDedupToSeq(d.data,data[i]))
  d.len = data.len.uint32

proc init*[T](_: typedesc[DictComp], data: sink seq[T]): DictComp[T] =
  comprSeq(result, data)

proc `[]`*[T](d: DictComp[T], idx: int): T =
  return d.data[d.idx[idx]]

proc `[]=`*[T](d: var DictComp[T], idx: int, x: T) =
  d.idx[idx] = addDedupToSeq(d.data, x)

proc `&=`*[T](d: var DictComp[T], x: T) =
  d.idx.add(addDedupToSeq(d.data, x))
  inc d.len

proc `$`*[T](d: DictComp[T]): string =
  $d.toSeq




#[
var data = @["1","1","2","3","3"]
var data2 = @[@[2,2,2,2],@[2,2,2,2],@[2,2,1],@[2,2,1],@[1,2,1]]
var x = DictComp.init(data)
var y = DictComp.init(data2)

echo data
echo x.data
echo x.idx
echo x.toSeq
echo x
echo y.data
echo y
y &= @[3,3,3,3]
y &= @[3,3,3,3]
echo y.data
echo y
y[0] = @[1]
echo y]#