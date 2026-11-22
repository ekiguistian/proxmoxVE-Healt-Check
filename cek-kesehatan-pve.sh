#!/bin/bash

# Warna Terminal
RED='\033[1;31m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
ORANGE='\033[38;5;208m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

# Inisialisasi Penghitung Status
COUNT_OK=0
COUNT_WARN=0
COUNT_CRIT=0

# Fungsi Cetak Status
print_ok() {
    echo -e "  [${GREEN}AMAN / OK${NC}] $1"
    ((COUNT_OK++))
}

print_warn() {
    echo -e "  [${YELLOW}PERLU PERHATIAN${NC}] $1"
    echo -e "     ${YELLOW}└─ Solusi:${NC} $2"
    ((COUNT_WARN++))
}

print_crit() {
    echo -e "  [${RED}PERLU PERBAIKAN${NC}] $1"
    echo -e "     ${RED}└─ Solusi:${NC} $2"
    ((COUNT_CRIT++))
}

# Mengambil Informasi Spesifikasi Hardware & Sistem
PVE_VER=$(pveversion 2>/dev/null | cut -d'/' -f2 || echo "Tidak terdeteksi")
CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d':' -f2 | sed 's/^ //;s/  */ /g')
CPU_CORES=$(nproc)
CPU_SOCKETS=$(lscpu 2>/dev/null | awk '/Socket\(s\):/ {print $2}')
[ -z "$CPU_SOCKETS" ] && CPU_SOCKETS=1

# Deteksi Suhu CPU
CPU_TEMP="Tidak terbaca"
if [ -d /sys/class/thermal/thermal_zone0 ]; then
    RAW_TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    if [ -n "$RAW_TEMP" ] && [ "$RAW_TEMP" -gt 0 ]; then
        CPU_TEMP="$((RAW_TEMP / 1000))°C"
    fi
fi

RAM_TOTAL_GB=$(awk '/MemTotal/ {printf "%.2f GB", $2/1024/1024}' /proc/meminfo)
BOARD_VENDOR=$(cat /sys/devices/virtual/dmi/id/board_vendor 2>/dev/null)
BOARD_NAME=$(cat /sys/devices/virtual/dmi/id/board_name 2>/dev/null)
SYS_MODEL="${BOARD_VENDOR} ${BOARD_NAME}"
[ -z "$(echo "$SYS_MODEL" | tr -d ' ')" ] && SYS_MODEL="Virtual / Tidak Terdeteksi"

IP_ADDR=$(hostname -I | awk '{print $1}')
GATEWAY_IP=$(ip route | awk '/default/ {print $3; exit}')
[ -z "$GATEWAY_IP" ] && GATEWAY_IP="Tidak ada"
DNS_SERVERS=$(awk '/^nameserver/ {printf "%s ", $2}' /etc/resolv.conf | xargs)
[ -z "$DNS_SERVERS" ] && DNS_SERVERS="Tidak diset"

# Statistik VM & Container
VM_RUN=$(qm list 2>/dev/null | grep -c "running" || echo 0)
VM_STOP=$(qm list 2>/dev/null | grep -c "stopped" || echo 0)
CT_RUN=$(pct list 2>/dev/null | grep -c "running" || echo 0)
CT_STOP=$(pct list 2>/dev/null | grep -c "stopped" || echo 0)

clear
echo -e "${ORANGE}${BOLD}"
cat << "EOF"
    ____                                       _    ________
   / __ \_________  _  ______ ___  ____  _  __| |  / / ____/
  / /_/ / ___/ __ \| |/_/ __ `__ \/ __ \| |/_/| | / / __/   
 / ____/ /  / /_/ />  </ / / / / / /_/ />  <  | |/ / /___   
/_/   /_/   \____/_/|_|_/ /_/ /_/\____/_/|_|  |___/_____/   
EOF
echo -e "${NC}${CYAN}${BOLD}==============================================================================${NC}"
echo -e "${WHITE}${BOLD}                 LAPORAN DIAGNOSIS & KESEHATAN SERVER PROXMOX                 ${NC}"
echo -e "${CYAN}${BOLD}==============================================================================${NC}"
echo -e "${BOLD}SPESIFIKASI HARDWARE & INFORMASI NODE:${NC}"
echo -e "  • Hostname / IP    : ${WHITE}$(hostname)${NC} (${IP_ADDR}) | Gateway: ${GATEWAY_IP}"
echo -e "  • Versi Proxmox    : PVE ${PVE_VER} | Kernel: $(uname -r)"
echo -e "  • Waktu Audit      : $(date '+%d %B %Y %H:%M:%S')"
echo -e "  • Uptime Server    : $(uptime -p | sed 's/up //')"
echo -e "  • Motherboard      : ${SYS_MODEL}"
echo -e "  • Prosesor (CPU)   : ${CPU_MODEL} (${CPU_SOCKETS} Socket, ${CPU_CORES} vCPU) | Suhu: ${CPU_TEMP}"
echo -e "  • Kapasitas RAM    : ${RAM_TOTAL_GB}"
echo -e "  • Beban Kerja      : VM (${GREEN}${VM_RUN} Aktif${NC} / ${GRAY}${VM_STOP} Mati${NC}) | Container LXC (${GREEN}${CT_RUN} Aktif${NC} / ${GRAY}${CT_STOP} Mati${NC})"

echo -e "${CYAN}------------------------------------------------------------------------------${NC}"
echo -e "${BOLD}PERANGKAT JARINGAN (NIC FISIK & BRIDGE PROXMOX):${NC}"
for IFACE_PATH in /sys/class/net/*; do
    IFACE=$(basename "$IFACE_PATH")
    if [[ "$IFACE" =~ ^(lo|tap|veth|fwbr|fwln|fwpr) ]]; then
        continue
    fi

    OPERSTATE=$(cat "$IFACE_PATH/operstate" 2>/dev/null)
    MAC_ADDR=$(cat "$IFACE_PATH/address" 2>/dev/null)
    IFACE_IP=$(ip -4 -o addr show "$IFACE" 2>/dev/null | awk '{print $4}' | paste -sd "," -)
    [ -z "$IFACE_IP" ] && IFACE_IP="Tanpa IP"

    if [ -d "$IFACE_PATH/device" ]; then
        DRIVER=$(basename "$(readlink -f "$IFACE_PATH/device/driver" 2>/dev/null)" 2>/dev/null)
        [ -z "$DRIVER" ] && DRIVER="-"
        SPEED=$(cat "$IFACE_PATH/speed" 2>/dev/null)
        DUPLEX=$(cat "$IFACE_PATH/duplex" 2>/dev/null)
        MASTER_BR=$(basename "$(readlink -f "$IFACE_PATH/master" 2>/dev/null)" 2>/dev/null)
        
        if [ "$OPERSTATE" == "up" ]; then
            STATE_TXT="${GREEN}UP${NC}"
            if [ -n "$SPEED" ] && [ "$SPEED" -gt 0 ] 2>/dev/null; then
                if [ "$SPEED" -ge 1000 ]; then
                    SPEED_TXT="${GREEN}${SPEED}Mbps (${DUPLEX})${NC}"
                else
                    SPEED_TXT="${YELLOW}${SPEED}Mbps (${DUPLEX})${NC}"
                fi
            else
                SPEED_TXT="Speed N/A"
            fi
        else
            STATE_TXT="${RED}DOWN${NC}"
            SPEED_TXT="${GRAY}Terputus${NC}"
        fi

        BR_INFO=""
        [ -n "$MASTER_BR" ] && [ "$MASTER_BR" != "device" ] && BR_INFO=" -> Bridge: ${CYAN}${MASTER_BR}${NC}"

        echo -e "  • ${WHITE}${IFACE}${NC} [NIC Fisik] : Status: ${STATE_TXT} | Link: ${SPEED_TXT} | Driver: ${DRIVER} | MAC: ${MAC_ADDR}${BR_INFO}"
    elif [ -d "$IFACE_PATH/bridge" ]; then
        PORTS=$(ls "$IFACE_PATH/brif" 2>/dev/null | grep -vE '^(tap|veth|fw)' | tr '\n' ',' | sed 's/,$//')
        [ -z "$PORTS" ] && PORTS="Tidak ada port fisik"
        if [ "$OPERSTATE" == "up" ] || [ "$OPERSTATE" == "unknown" ]; then
            STATE_TXT="${GREEN}AKTIF${NC}"
        else
            STATE_TXT="${RED}DOWN${NC}"
        fi
        echo -e "  • ${CYAN}${IFACE}${NC} [Bridge]   : Status: ${STATE_TXT} | IP: ${WHITE}${IFACE_IP}${NC} | Port Fisik: ${PORTS}"
    fi
done

echo -e "${CYAN}------------------------------------------------------------------------------${NC}"
echo -e "${BOLD}DAFTAR PERANGKAT PENYIMPANAN FISIK (DISK & SUHU):${NC}"

for DISK in $(lsblk -d -n -o NAME,TYPE | awk '$2=="disk" {print "/dev/"$1}'); do
    D_SIZE=$(lsblk -d -n -o SIZE "$DISK" | xargs)
    D_MODEL=$(lsblk -d -n -o MODEL "$DISK" | xargs)
    [ -z "$D_MODEL" ] && D_MODEL="Virtual/RAID Disk"
    
    D_TEMP="-"
    D_HEALTH="N/A"
    if command -v smartctl &> /dev/null; then
        SMART_ALL=$(smartctl -a "$DISK" 2>/dev/null)
        if echo "$SMART_ALL" | grep -qE "PASSED|OK"; then
            D_HEALTH="${GREEN}PASSED${NC}"
        elif echo "$SMART_ALL" | grep -q "FAILED"; then
            D_HEALTH="${RED}FAILED${NC}"
        fi
        
        TEMP_VAL=$(echo "$SMART_ALL" | awk '/Temperature:/ {print $2; exit}')
        [ -z "$TEMP_VAL" ] && TEMP_VAL=$(echo "$SMART_ALL" | awk '/Temperature_Celsius/ {print $10; exit}')
        if [ -n "$TEMP_VAL" ]; then
            if [ "$TEMP_VAL" -ge 60 ]; then
                D_TEMP="${RED}${TEMP_VAL}°C${NC}"
            elif [ "$TEMP_VAL" -ge 50 ]; then
                D_TEMP="${YELLOW}${TEMP_VAL}°C${NC}"
            else
                D_TEMP="${GREEN}${TEMP_VAL}°C${NC}"
            fi
        fi
    fi
    echo -e "  • ${WHITE}${DISK}${NC} : ${D_MODEL} (${D_SIZE}) | Suhu: ${D_TEMP} | S.M.A.R.T: ${D_HEALTH}"
done
echo -e "${CYAN}${BOLD}==============================================================================${NC}\n"

# 1. PEMERIKSAAN KERNEL & REBOOT
echo -e "${BOLD}1. SISTEM, KERNEL & SUHU CPU${NC}"
RUNNING_KERNEL=$(uname -r)
LATEST_KERNEL=$(ls -v /boot/vmlinuz-* 2>/dev/null | tail -n 1 | sed 's|/boot/vmlinuz-||')

if [ "$RUNNING_KERNEL" == "$LATEST_KERNEL" ]; then
    print_ok "Server menjalankan kernel terbaru ($RUNNING_KERNEL)."
else
    print_warn "Kernel berjalan ($RUNNING_KERNEL) berbeda dari kernel terpasang terbaru ($LATEST_KERNEL)." \
               "Lakukan 'reboot' server agar pembaruan kernel & keamanan terbaru aktif."
fi

if [ "$CPU_TEMP" != "Tidak terbaca" ]; then
    NUM_CPU_TEMP=${CPU_TEMP%°C}
    if [ "$NUM_CPU_TEMP" -lt 75 ]; then
        print_ok "Suhu prosesor CPU normal ($CPU_TEMP)."
    elif [ "$NUM_CPU_TEMP" -lt 88 ]; then
        print_warn "Suhu prosesor CPU cukup hangat ($CPU_TEMP)." \
                   "Periksa sirkulasi udara ruang server dan kebersihan kipas heatsink."
    else
        print_crit "Suhu prosesor CPU terlalu panas / overheating ($CPU_TEMP)!" \
                   "Segera periksa kipas pendingin CPU, pasta termal, dan suhu ruang server."
    fi
fi

# 2. PEMERIKSAAN CPU & BEBAN SISTEM
echo -e "\n${BOLD}2. PERFORMA CPU & LOAD AVERAGE${NC}"
LOAD_1M=$(awk '{print $1}' /proc/loadavg)
LOAD_PCT=$(awk "BEGIN {printf \"%.0f\", ($LOAD_1M / $CPU_CORES) * 100}")

if [ "$LOAD_PCT" -lt 70 ]; then
    print_ok "Beban CPU normal: Load $LOAD_1M pada $CPU_CORES Core (${LOAD_PCT}% kapasitas)."
elif [ "$LOAD_PCT" -lt 95 ]; then
    print_warn "Beban CPU cukup tinggi: Load $LOAD_1M pada $CPU_CORES Core (${LOAD_PCT}%)." \
               "Periksa VM/Container yang memakai CPU tinggi menggunakan perintah 'top' atau 'htop'."
else
    print_crit "Beban CPU overload: Load $LOAD_1M pada $CPU_CORES Core (${LOAD_PCT}%)." \
               "Segera cek VM yang mengalami hang/looping dan batasi alokasi vCPU jika perlu."
fi

# 3. PEMERIKSAAN PENGGUNAAN RAM & SWAP
echo -e "\n${BOLD}3. PENGGUNAAN MEMORI (RAM & SWAP)${NC}"
MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))

if [ "$MEM_PCT" -lt 80 ]; then
    print_ok "Penggunaan RAM aman: ${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PCT}%)."
elif [ "$MEM_PCT" -lt 92 ]; then
    print_warn "Penggunaan RAM mulai tinggi: ${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PCT}%)." \
               "Pertimbangkan mengurangi alokasi RAM VM atau aktifkan fitur memory ballooning."
else
    print_crit "Penggunaan RAM kritis: ${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PCT}%)." \
               "Risiko Out-Of-Memory (OOM) mematikan VM secara paksa. Matikan VM non-prioritas."
fi

SWAP_TOTAL=$(free -m | awk '/Swap:/ {print $2}')
SWAP_USED=$(free -m | awk '/Swap:/ {print $3}')
if [ "$SWAP_TOTAL" -gt 0 ]; then
    SWAP_PCT=$((SWAP_USED * 100 / SWAP_TOTAL))
    if [ "$SWAP_PCT" -lt 50 ]; then
        print_ok "Penggunaan Swap aman: ${SWAP_USED}MB / ${SWAP_TOTAL}MB (${SWAP_PCT}%)."
    else
        print_warn "Penggunaan Swap tinggi (${SWAP_PCT}%). Sistem mulai melambat." \
                   "Kurangi beban RAM atau restart VM yang mengalami memory leak."
    fi
fi

# 4. PEMERIKSAAN KAPASITAS PENYIMPANAN
echo -e "\n${BOLD}4. KAPASITAS PENYIMPANAN (FILESYSTEM, LVM-THIN & ZFS)${NC}"
while read -r PCT MOUNT AVAIL; do
    NUM_PCT=${PCT%\%}
    if [ "$NUM_PCT" -lt 80 ]; then
        print_ok "Partisi '$MOUNT' aman: Terpakai $PCT (Sisa $AVAIL)."
    elif [ "$NUM_PCT" -lt 90 ]; then
        print_warn "Partisi '$MOUNT' mulai penuh: Terpakai $PCT (Sisa $AVAIL)." \
                   "Hapus file ISO lama, template tidak terpakai, atau jalankan 'apt autoremove'."
    else
        print_crit "Partisi '$MOUNT' hampir penuh: Terpakai $PCT (Sisa $AVAIL)." \
                   "Segera kosongkan ruang! Partisi root/boot yang 100% penuh membuat Web UI & VM macet."
    fi
done < <(df -h -x tmpfs -x devtmpfs -x squashfs | awk 'NR>1 {print $5 " " $6 " " $4}')

if command -v lvs &> /dev/null; then
    while read -r LV VG DPCT; do
        INT_DPCT=${DPCT%.*}
        if [ "$INT_DPCT" -lt 80 ]; then
            print_ok "Storage LVM-Thin '$VG/$LV' aman: Terpakai ${DPCT}%."
        elif [ "$INT_DPCT" -lt 90 ]; then
            print_warn "Storage LVM-Thin '$VG/$LV' mulai penuh (${DPCT}%)." \
                       "Jalankan 'fstrim -av' di dalam VM Linux/Windows atau hapus snapshot lama."
        else
            print_crit "Storage LVM-Thin '$VG/$LV' kritis (${DPCT}%)." \
                       "Segera hapus snapshot VM atau tambah kapasitas disk fisik baru."
        fi
    done < <(lvs --noheadings -o lv_name,vg_name,data_percent 2>/dev/null | awk '$3 != "" {print $1 " " $2 " " $3}')
fi

if command -v zpool &> /dev/null; then
    ZPOOL_OUT=$(zpool status -x 2>/dev/null)
    if [[ "$ZPOOL_OUT" == *"all pools are healthy"* ]]; then
        print_ok "Semua ZFS Pool dalam kondisi sehat (ONLINE)."
    elif [ -n "$ZPOOL_OUT" ]; then
        print_crit "Masalah terdeteksi pada ZFS Pool!" \
                   "Jalankan 'zpool status' untuk melihat disk yang rusak/degraded dan segera ganti disk."
    fi
fi

# 5. AUDIT MENDALAM S.M.A.R.T
echo -e "\n${BOLD}5. AUDIT MENDALAM S.M.A.R.T (SUHU, WEAR LEVEL & BAD SECTOR)${NC}"
if command -v smartctl &> /dev/null; then
    for DISK in $(lsblk -d -n -o NAME,TYPE | awk '$2=="disk" {print "/dev/"$1}'); do
        SMART_DATA=$(smartctl -a "$DISK" 2>/dev/null)
        
        if echo "$SMART_DATA" | grep -qE "PASSED|OK"; then
            POH=$(echo "$SMART_DATA" | awk '/Power_On_Hours/ {print $10; exit}')
            [ -z "$POH" ] && POH=$(echo "$SMART_DATA" | awk '/Power On Hours:/ {gsub(/,/, "", $4); print $4; exit}')
            POH_INFO=""
            [ -n "$POH" ] && POH_INFO=" | Jam Nyala: ${POH} jam"
            
            print_ok "Disk $DISK lulus uji S.M.A.R.T (PASSED${POH_INFO})."
        elif echo "$SMART_DATA" | grep -q "FAILED"; then
            print_crit "Disk $DISK GAGAL uji S.M.A.R.T (Rusak/Akan Mati)!" \
                       "Segera backup seluruh VM/CT dan ganti fisik disk $DISK secepatnya!"
        else
            print_warn "Atribut S.M.A.R.T $DISK tidak dapat dibaca langsung (RAID Hardware/Virtual)." \
                       "Periksa status kesehatan disk melalui utilitas RAID controller (storcli/perccli/hpssacli)."
            continue
        fi

        TEMP_DISK=$(echo "$SMART_DATA" | awk '/Temperature:/ {print $2; exit}')
        [ -z "$TEMP_DISK" ] && TEMP_DISK=$(echo "$SMART_DATA" | awk '/Temperature_Celsius/ {print $10; exit}')
        if [ -n "$TEMP_DISK" ]; then
            if [ "$TEMP_DISK" -lt 50 ]; then
                print_ok "Suhu disk $DISK ideal (${TEMP_DISK}°C)."
            elif [ "$TEMP_DISK" -lt 60 ]; then
                print_warn "Suhu disk $DISK mulai hangat (${TEMP_DISK}°C)." \
                           "Pastikan aliran udara casing server lancar atau tambahkan heatsink pada NVMe."
            else
                print_crit "Suhu disk $DISK terlalu panas / overheating (${TEMP_DISK}°C)!" \
                           "Performa SSD akan melambat (thermal throttling) & umur chip memendek. Perbaiki pendinginan!"
            fi
        fi

        WEAR_NVME=$(echo "$SMART_DATA" | awk '/Percentage Used:/ {gsub(/%/, "", $3); print $3; exit}')
        if [ -n "$WEAR_NVME" ]; then
            REMAIN_LIFE=$((100 - WEAR_NVME))
            if [ "$WEAR_NVME" -lt 80 ]; then
                print_ok "Kesehatan sel NAND NVMe $DISK masih prima (Terpakai ${WEAR_NVME}%, Sisa umur ${REMAIN_LIFE}%)."
            elif [ "$WEAR_NVME" -lt 95 ]; then
                print_warn "Tingkat keausan NVMe $DISK sudah tinggi (Terpakai ${WEAR_NVME}%, Sisa umur ${REMAIN_LIFE}%)." \
                           "Siapkan unit SSD pengganti dalam waktu dekat sebelum mencapai batas tulis."
            else
                print_crit "Umur tulis NVMe $DISK hampir habis (Terpakai ${WEAR_NVME}%, Sisa ${REMAIN_LIFE}%)!" \
                           "Segera kloning/migrasi data dan ganti SSD $DISK sebelum berubah menjadi Read-Only."
            fi
        fi

        REALLOC=$(echo "$SMART_DATA" | awk '/Reallocated_Sector_Ct/ {print $10; exit}')
        PENDING=$(echo "$SMART_DATA" | awk '/Current_Pending_Sector/ {print $10; exit}')
        MEDIA_ERR=$(echo "$SMART_DATA" | awk '/Media and Data Integrity Errors:/ {print $6; exit}')
        
        if [ -n "$REALLOC" ] && [ "$REALLOC" -gt 0 ]; then
            print_warn "Ditemukan $REALLOC bad sector yang direlokasi pada $DISK." \
                       "Pantau angka ini setiap minggu. Jika terus bertambah, segera ganti disk."
        fi
        if [ -n "$PENDING" ] && [ "$PENDING" -gt 0 ]; then
            print_crit "Ditemukan $PENDING sektor rusak tertunda (Pending Sector) pada $DISK!" \
                       "Risiko korupsi data tinggi. Backup VM segera dan ganti disk $DISK."
        fi
        if [ -n "$MEDIA_ERR" ] && [ "$MEDIA_ERR" -gt 0 ]; then
            print_crit "Ditemukan $MEDIA_ERR Media/Data Integrity Errors pada NVMe $DISK!" \
                       "Segera backup data dan klaim garansi atau ganti unit NVMe."
        fi
    done
else
    print_warn "Paket 'smartmontools' tidak terpasang." \
               "Jalankan 'apt update && apt install -y smartmontools' untuk memeriksa suhu & kesehatan SSD/HDD."
fi

# 6. KESEHATAN JARINGAN
echo -e "\n${BOLD}6. KESEHATAN JARINGAN (NIC, PACKET ERROR, GATEWAY & DNS)${NC}"
for IFACE_PATH in /sys/class/net/*; do
    IFACE=$(basename "$IFACE_PATH")
    if [ -d "$IFACE_PATH/device" ]; then
        OPERSTATE=$(cat "$IFACE_PATH/operstate" 2>/dev/null)
        SPEED=$(cat "$IFACE_PATH/speed" 2>/dev/null)
        RX_ERR=$(cat "$IFACE_PATH/statistics/rx_errors" 2>/dev/null || echo 0)
        TX_ERR=$(cat "$IFACE_PATH/statistics/tx_errors" 2>/dev/null || echo 0)
        RX_DROP=$(cat "$IFACE_PATH/statistics/rx_dropped" 2>/dev/null || echo 0)
        TX_DROP=$(cat "$IFACE_PATH/statistics/tx_dropped" 2>/dev/null || echo 0)
        TOTAL_ERR=$((RX_ERR + TX_ERR))

        if [ "$OPERSTATE" == "up" ]; then
            if [ -n "$SPEED" ] && [ "$SPEED" -lt 1000 ] 2>/dev/null; then
                print_warn "NIC fisik '$IFACE' berjalan di kecepatan rendah (${SPEED}Mbps)." \
                           "Periksa kabel LAN (gunakan minimal Cat5e/Cat6) atau port switch/router Anda."
            else
                print_ok "NIC fisik '$IFACE' terhubung optimal (${SPEED:-1000}Mbps)."
            fi

            if [ "$TOTAL_ERR" -gt 100 ]; then
                print_warn "Terdeteksi $TOTAL_ERR packet error pada '$IFACE' (Drop RX/TX: $RX_DROP/$TX_DROP)." \
                           "Ganti kabel jaringan atau periksa port switch yang mungkin bermasalah."
            fi
        else
            MASTER_BR=$(basename "$(readlink -f "$IFACE_PATH/master" 2>/dev/null)" 2>/dev/null)
            if [ -n "$MASTER_BR" ] && [ "$MASTER_BR" != "device" ]; then
                print_crit "NIC fisik '$IFACE' yang terhubung ke '$MASTER_BR' dalam status DOWN (Terputus)!" \
                           "Periksa kabel LAN fisik, lampu indikator port RJ45/SFP, atau switch jaringan."
            else
                print_ok "NIC fisik '$IFACE' tidak digunakan (DOWN - tidak terikat ke bridge)."
            fi
        fi
    fi
done

if [ "$GATEWAY_IP" != "Tidak ada" ]; then
    if ping -c 1 -W 2 "$GATEWAY_IP" &> /dev/null; then
        print_ok "Koneksi ke Gateway lokal ($GATEWAY_IP) lancar."
    else
        print_crit "Server gagal menghubungi Gateway ($GATEWAY_IP)!" \
                   "Periksa kabel jaringan, VLAN, atau pengaturan IP/Netmask di '/etc/network/interfaces'."
    fi
else
    print_crit "Default Gateway jaringan tidak ditemukan!" \
               "Tambahkan baris 'gateway <IP-Router>' pada interface vmbr0 di Proxmox Web UI -> Network."
fi

if ping -c 1 -W 2 1.1.1.1 &> /dev/null; then
    if getent hosts download.proxmox.com &> /dev/null; then
        print_ok "Koneksi Internet & DNS ($DNS_SERVERS) berfungsi normal."
    else
        print_warn "Koneksi internet tersambung, tetapi resolusi DNS gagal ($DNS_SERVERS)." \
                   "Periksa pengaturan DNS di Proxmox Web UI -> System -> DNS (misal: 1.1.1.1 / 8.8.8.8)."
    fi
else
    print_warn "Server tidak dapat menjangkau internet luar (1.1.1.1)." \
               "Periksa routing internet pada router/firewall utama Anda."
fi

# 7. LAYANAN INTI PROXMOX
echo -e "\n${BOLD}7. LAYANAN INTI PROXMOX (SERVICES)${NC}"
SERVICES=("pveproxy" "pvedaemon" "pvestatd" "corosync" "sshd")
for SVC in "${SERVICES[@]}"; do
    if systemctl list-unit-files | grep -q "^${SVC}.service"; then
        if systemctl is-active --quiet "$SVC"; then
            print_ok "Layanan '$SVC' berjalan normal."
        else
            if [ "$SVC" == "corosync" ]; then
                print_warn "Layanan '$SVC' tidak aktif (Normal untuk server tunggal / non-cluster)." \
                           "Abaikan jika server tidak tergabung dalam cluster Proxmox."
            else
                print_crit "Layanan penting '$SVC' MATI!" \
                           "Jalankan 'systemctl restart $SVC' dan periksa error dengan 'journalctl -u $SVC -n 30'."
            fi
        fi
    fi
done

# 8. BOOTLOADER & EFI
echo -e "\n${BOLD}8. BOOTLOADER & EFI${NC}"
if [ -d /sys/firmware/efi ]; then
    FORCE_EFI=$(debconf-show grub-efi-amd64 2>/dev/null | grep "force_efi_extra_removable" | awk '{print $NF}')
    if [ "$FORCE_EFI" == "true" ]; then
        print_ok "Sinkronisasi bootloader cadangan UEFI (BOOTX64.efi) aktif."
    else
        print_warn "Bootloader cadangan UEFI belum diset otomatis update." \
                   "Jalankan: echo 'grub-efi-amd64 grub2/force_efi_extra_removable boolean true' | debconf-set-selections -v -u && apt install --reinstall grub-efi-amd64"
    fi
else
    print_ok "Sistem menggunakan mode Legacy BIOS (tidak memerlukan sinkronisasi EFI)."
fi

# RINGKASAN AKHIR
echo -e "\n${CYAN}${BOLD}==============================================================================${NC}"
echo -e "${BOLD}RINGKASAN AKHIR PEMERIKSAAN KESEHATAN:${NC}"
echo -e "  ${GREEN}● Aman / OK        :${NC} $COUNT_OK item"
echo -e "  ${YELLOW}● Perlu Perhatian  :${NC} $COUNT_WARN item"
echo -e "  ${RED}● Perlu Perbaikan  :${NC} $COUNT_CRIT item"
echo -e "${CYAN}${BOLD}==============================================================================${NC}"

if [ "$COUNT_CRIT" -gt 0 ]; then
    echo -e "${RED}${BOLD}KESIMPULAN: Ditemukan masalah kritis! Segera ikuti solusi berwarna MERAH di atas.${NC}\n"
elif [ "$COUNT_WARN" -gt 0 ]; then
    echo -e "${YELLOW}${BOLD}KESIMPULAN: Server berjalan normal, namun ada catatan yang perlu diperhatikan (KUNING).${NC}\n"
else
    echo -e "${GREEN}${BOLD}KESIMPULAN: Server Proxmox dalam kondisi SANGAT PRIMA & SEHAT!${NC}\n"
fi
