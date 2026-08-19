//%attributes = {}
$in:="# header\r* item\r* item"
$out:=CPP Markdown ($in)

$path:=System folder:C487(Desktop:K41:16)+"jwevent.svg"

READ PICTURE FILE:C678($path;$image)

$path:=System folder:C487(Desktop:K41:16)+"jwevent.png"

TRANSFORM PICTURE:C988($image;Scale:K61:2;10;10)
WRITE PICTURE FILE:C680($path;$image)