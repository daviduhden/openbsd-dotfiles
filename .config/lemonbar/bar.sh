#!/bin/ksh
#FONT="-misc-fixed-medium-r-normal--15-140-75-75-c-90-iso10646-1"
FONT="JetBrainsMono Nerd Font Mono:size=7"
BG="#1a1a2e"
FG="#a9b1d6"
ACC="#7fa8d1"
GRN="#26a65b"
PRP="#c678dd"
RED="#e06c75"

get_time() { date "+%H:%M:%S  %d.%m.%Y"; }

get_desktop() {
  cur=$(xprop -root -notype _NET_CURRENT_DESKTOP 2>/dev/null | awk '{print $3}')
  [ -z "$cur" ] && cur=0
  out=""
  for i in 1 2 3 4 5 6; do
    if [ "$i" -eq "$cur" ]; then
      out="${out}%{F$BG}%{B$ACC} $i %{B$BG}%{F$FG} "
    else
      out="${out}%{F$FG} $i  "
    fi
  done
  echo "$out"
}

get_cpu() {
  top -b -s1 -d2 | awk '
    /^CPU[0-9]+ states/ {
        cpu_nr = substr($1, 4)
        gsub(/:/, "", cpu_nr)
        for (i=1; i<=NF; i++) {
            if ($i == "idle") {
                idle = $(i-1)
                gsub(/%/, "", idle)
                used = 100 - idle
                data[cpu_nr] = used
                if (cpu_nr+0 > maxcpu) maxcpu = cpu_nr+0
            }
        }
    }
    END {
        total = 0
        cores = ""
        for (i=0; i<=maxcpu; i++) {
            total += data[i]
            cores = cores sprintf("%3.0f%% ", data[i])
        }
        avg = total / (maxcpu+1)
        printf "%.0f|%s\n", avg, cores
    }'
}

old_format() {
  awk -v n="$1" 'BEGIN {
    s = ""
    m = ""
    while (n > 0) {
      r = int(n % 1000)
      if (s == "") { s = sprintf("%d", r) }
      else { s = sprintf("%d.%d", r, s) }
      n = int(n / 1000)
    }
    print s
  }'
}

format() {
  awk -v n="$1" 'BEGIN {
    if (n >= 1000)
      printf "%d.%03d\n", int(n / 1000), n % 1000
    else
      printf "%d\n", n
  }'
}

get_ram() {
  act=$(top -b -d1 | awk '/^Memory/ {
        split($3, a, "/")
        gsub(/M$/, "", a[1])
        print a[1]
        exit
    }')

  total=$(sysctl -n hw.usermem | awk '{printf "%.0f", $1/1024/1024}')

  act=$(format "$act")
  total=$(format "$total")

  echo "${act} MB / ${total} MB"
}

get_bat() {
  pct=$(apm -l 2>/dev/null)
  ac=$(apm -a 2>/dev/null)

  [ -z "$pct" ] && return

  if [ "$ac" = "1" ]; then
    icon=""
  else
    if [ "$pct" -ge 90 ]; then
      icon=""
    elif [ "$pct" -ge 65 ]; then
      icon=""
    elif [ "$pct" -ge 40 ]; then
      icon=""
    elif [ "$pct" -ge 15 ]; then
      icon=""
    else
      icon=""
    fi
  fi

  echo "$icon ${pct}%"
}

get_net() {
  if ifconfig em0 2>/dev/null | grep -q "status: active"; then
    ip=$(ifconfig em0 | awk '/inet / {print $2}')
    echo "󰈀 em0 $ip"
    return
  fi

  if ifconfig iwm0 2>/dev/null | grep -q "status: active"; then
    ssid=$(ifconfig iwm0 | awk '/ieee80211/ {print $3}')
    ip=$(ifconfig iwm0 | awk '/inet / {print $2}')
    echo " iwm0 $ssid $ip"
  elif ifconfig iwm0 2>/dev/null | grep -q "inet "; then
    ip=$(ifconfig iwm0 | awk '/inet / {print $2}')
    echo " iwm0 $ip"
  else
    echo "󰖪 offline"
  fi
}

get_traffic() {
  iface="iwm0"
  state="/tmp/lemonbar_${iface}_net"

  format_rate() {
    bytes=$1
    if [ "$bytes" -ge 1048576 ]; then
      rate=$(awk "BEGIN {printf \"%.1fM/s\", $bytes/1048576}")
    elif [ "$bytes" -ge 1024 ]; then
      rate=$(awk "BEGIN {printf \"%.1fK/s\", $bytes/1024}")
    else
      rate="${bytes}B/s"
    fi
    printf "%8s" "$rate"
  }

  set -- $(netstat -nib -I "$iface" | awk 'NR==2 {print $5, $6}')
  rx=$1
  tx=$2
  now=$(date +%s)

  if [ -f "$state" ]; then
    read -r old_rx old_tx old_time <"$state"

    elapsed=$((now - old_time))
    [ "$elapsed" -le 0 ] && elapsed=1

    rx_diff=$((rx - old_rx))
    tx_diff=$((tx - old_tx))

    # Negative Werte abfangen (Interface-Reset, Zaehler-Wraparound)
    [ "$rx_diff" -lt 0 ] && rx_diff=0
    [ "$tx_diff" -lt 0 ] && tx_diff=0

    rx_rate=$((rx_diff / elapsed))
    tx_rate=$((tx_diff / elapsed))

    echo "↓$(format_rate "$rx_rate") ↑$(format_rate "$tx_rate")"
  else
    echo "↓0B/s ↑0B/s"
  fi

  echo "$rx $tx $now" >"$state"
}

get_tor() {
  if rcctl check tor >/dev/null 2>&1; then
    printf "◉"
  else
    printf " "
  fi
}

while true; do
  TIME=$(get_time)
  DESK=$(get_desktop)
  CPU_OUT=$(get_cpu)
  CPUAVG=$(echo "$CPU_OUT" | cut -d'|' -f1)
  CPU=$(echo "$CPU_OUT" | cut -d'|' -f2)
  RAM=$(get_ram)
  BAT=$(get_bat)
  NET=$(get_net)
  TRAFFIC=$(get_traffic)
  TOR=$(get_tor)
  if [ "$CPUAVG" -gt 80 ]; then
    CPUCOLOR="$RED"
  elif [ "$CPUAVG" -gt 50 ]; then
    CPUCOLOR="$PRP"
  else CPUCOLOR="$GRN"; fi
  BAT_PART=""
  [ -n "$BAT" ] && BAT_PART="%{F$ACC}$BAT  "
  echo "%{B$BG}%{F$FG} %{l}${DESK}    %{F$CPUCOLOR}CPU $CPU%{F$FG}    RAM $RAM %{c}$TIME %{r}%{F$ACC}$NET   $TRAFFIC $TOR  $BAT_PART"
  #echo "%{B$BG}%{F$FG} %{l}${DESK}%{c}%{F$ACC}%{F$FG}  $TIME  %{r}%{F$CPUCOLOR}CPU $CPU%{F$FG}  RAM $RAM %{F$ACC}$NET  $TRAFFIC   $BAT_PART"
  sleep 1
done | lemonbar-xft -g x30+0+0 -f "$FONT" -B "$BG" -F "$FG" -p
