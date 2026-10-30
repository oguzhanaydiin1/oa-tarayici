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
  lines=$(grep -n -iE "error|exception|failed|what went wrong|undefined|isn't|can't|cannot|not found|\.dart:[0-9]+" "$log" \
          | grep -viE "^[0-9]+:\s*$|deprecated" | head -120 | cut -c1-300)
  [[ -z "$lines" ]] && lines=$(tail -60 "$log" | cut -c1-300)
  msg=$(printf '%s' "$lines" | sed -e 's/%/%25/g' | awk 'BEGIN{ORS="%0A"}{print}')
  level=error; [[ "$label" == "analiz" ]] && level=warning
  echo "::$level title=$label::$msg"
fi
exit $code
