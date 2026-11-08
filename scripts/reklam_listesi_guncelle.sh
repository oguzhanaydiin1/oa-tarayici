#!/usr/bin/env bash
# lib/adblock_list.dart dosyasını Peter Lowe listesinin güncel kopyasıyla yeniden yazar.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp)
curl -sSf https://raw.githubusercontent.com/StevenBlack/hosts/master/data/yoyo.org/hosts -o "$tmp"
python3 - "$tmp" <<'PY'
import sys,re
doms=sorted({l.split()[1] for l in open(sys.argv[1]) if l.startswith('0.0.0.0 ')})
skip={'analytics.google.com','c.apple.com'}
doms=[d for d in doms if d not in skip and re.fullmatch(r'[a-z0-9.-]+',d)]
out=["// Peter Lowe'un reklam ve izleyici sunucuları listesi (pgl.yoyo.org/adservers, StevenBlack/hosts",
"// deposundaki kopyasından). Yaygın reklam engelleyicilerin varsayılan listelerinden biri; siteleri",
"// bozmamasıyla bilinir. Güncellemek için: scripts/reklam_listesi_guncelle.sh",
"// ignore_for_file: lines_longer_than_80_chars","","const kAdServerList = <String>["]
line="  "
for d in doms:
    item=f"'{d}', "
    if len(line)+len(item)>110: out.append(line.rstrip()); line="  "
    line+=item
out.append(line.rstrip()); out.append("];")
open('lib/adblock_list.dart','w').write("\n".join(out)+"\n")
print(len(doms), 'alan adı')
PY
rm -f "$tmp"
