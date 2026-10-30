#!/usr/bin/env bash
# Bir komutu çalıştırır; başarısız olursa çıktının hata satırlarını GitHub "annotation" olarak yazar,
# böylece hata kaydı indirilmeden de görülebilir.
# Kullanım: bash scripts/ozetle.sh <etiket> <komut...>
set -uo pipefail
label="$1"; shift
log="ozet-$label.log"
"$@" 2>&1 | tee "$log"
code=${PIPESTATUS[0]}
if [[ $code -ne 0 || "$label" == "analiz" ]]; then
  # Hata içeren satırlar ve hemen çevreleri; en fazla 120 satır
  lines=$( { grep -n -A12 "What went wrong" "$log"; \
             grep -n -iE -B1 -A3 "error[ :]|error C[0-9]|error MSB|exception|\.dart:[0-9]+:[0-9]+|undefined|isn't defined|can't be|cannot|not found|requires|incompatible|minSdk|namespace|nuget"  "$log"; } \
          | grep -viE "^[0-9]+[:-]\s*$|Node\.js 20" | awk '!seen[$0]++' | head -220 | cut -c1-260)
  [[ -z "$lines" ]] && lines=$(tail -60 "$log" | cut -c1-300)
  msg=$(printf '%s' "$lines" | sed -e 's/%/%25/g' | awk 'BEGIN{ORS="%0A"}{print}')
  level=error; [[ "$label" == "analiz" ]] && level=warning
  echo "::$level title=$label::$msg"
fi
exit $code
