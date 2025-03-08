#!/bin/bash

# Function for case 1: No argument given
case_no_argument() {
    printf "%-10s %-10s %-10s %s\n" "PID" "TTY" "TIME" "CMD"
    term=$(tty | sed 's|/dev/pts/||') # getting the terminal
    pids=$(pgrep -t pts/$term) # getting the pids with the same terminal
    tts_output=$(tty | sed 's|/dev/||')
    for pid in $pids; do
        if [ -d "/proc/$pid" ]; then
            cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline") 
            cmd_name=$(echo "$cmd" | awk '{print $1}') # getting the command
            stat=$(<"/proc/$pid/stat") 
            utime=$(echo $stat | awk '{print $14}') # getting values of variables from the stat file
            stime=$(echo $stat | awk '{print $15}')
            total_time=$((utime + stime))
            total_time=$((total_time / 100)) # divide by 100 to convert seconds to hundredths of a second
            time=$(printf "%02d:%02d:%02d" $((total_time / 3600)) $(( (total_time % 3600) / 60 )) $((total_time % 60)))
            printf "%-10s %-10s %s %s\n" "$pid" "$tts_output" "$time" "$cmd_name"
        fi
    done
}

# Function for case 2: -p argument
case_pid_argument() {
printf "%-5s %-20s %-10s %-s\n" "PID" "TTY" "TIME" "CMD"
for pid in "$@"; do
    if [ -d "/proc/$pid" ]; then
        cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline")
        cmd_name=$(echo "$cmd" | awk '{print $1}')
        tty=$(readlink /proc/$pid/fd/0 2>/dev/null | sed 's|/dev/||')
        if [ -f "/proc/$pid/stat" ]; then
            utime=$(echo $stat | awk '{print $14}')
            stime=$(echo $stat | awk '{print $15}')
            total_time=$((utime + stime))
            time=$(printf "%02d:%02d:%02d" $((total_time / 3600)) $(( (total_time % 3600) / 60 )) $((total_time % 60)))
        fi
        if [[ "$tty" = "" ]]; then 
            tty="?"
        fi
        printf "%-5s %-20s %-10s %-s\n" "$pid" "$tty" "$time" "$cmd_name"
    fi
done
}

# Function for case 3: -a argument
case_all_processes() {
    printf "%-5s %-20s %-10s %-s\n" "PID" "TTY" "TIME" "CMD"
    xyz=($(pgrep "")) 
    for pid in "${xyz[@]}"; do
        cd /proc/$pid
        ppy=$(readlink /proc/$pid fd/0)
        cmd=$(awk '{print $2}' /proc/$pid/stat)
        if [[ "$cmd" != "(gnome-session-b)" ]]; then
            if [[ "$ppy" != "/dev/null" ]] && [[ "$ppy" != "" ]] && [[ "$ppy" != "pipe:"* ]] && [[ "$ppy" != "socket"* ]]; then
                sesid=$(awk '{print $6}' /proc/$pid/stat)
                if [[ "$sesid" != "$pid" ]];then
                    time=$(awk '{print $14 + $15}' "/proc/$pid/stat") # User + system time in jiffies
                    uTime=$(echo "scale=2; $time/100" | bc) # Assuming 100 jiffies per second
                    int=$(printf "%.0f" "$uTime")
                    utime=$(date -u --date="@$int" | cut -f 5 -d " ")
                    printf "%-5s %-20s %-10s %-s\n" "$pid" "${ppy#/dev/}" "$utime" "$cmd"
                fi
            fi
        fi
        if [[ "$cmd" == "(gnome-session-b)" ]]; then
            time=$(awk '{print $14 + $15}' "/proc/$pid/stat") # User + system time in jiffies
            uTime=$(echo "scale=2; $time/100" | bc) # Assuming 100 jiffies per second
            int=$(printf "%.0f" "$uTime")
            utime=$(date -u --date="@$int" | cut -f 5 -d " ")
            printf "%-5s %-20s %-10s %-s\n" "$pid" "${ppy#/dev/}" "$utime" "$cmd"  # Print the PID of gnome-session-b
        fi
    done
}

# Function for case 4: -u argument
case_user_processes() {
    echo -e "USER\tPID\t%CPU\t%MEM\tVSZ\tRSS\tTTY\tSTART\tTIME\tCOMMAND"  
    pgrep -u "$USER" | while read -r pid; do
        if [ -d "/proc/$pid" ]; then
            cmd=$(tr '\0' ' ' < /proc/$pid/cmdline)
            tty=$(readlink /proc/$pid/fd/0 2>/dev/null | sed 's|/dev/||')
            if [ -z "$tty" ] || [ "$tty" = "null" ]; then
                continue
            fi
            vmsize=$(awk '/VmSize/{print $2}' /proc/$pid/status)
            rsssize=$(awk '/^VmRSS/{print $2}' /proc/$pid/status)

            # Get system uptime in seconds
            CPU_SYS_ST_SEC=$(awk '{print $1}' /proc/uptime | cut -d '.' -f 1)
            STAT_DATA=$(cat /proc/$pid/stat)
            PID_START_TIME_TICKS=$(echo $STAT_DATA | cut -f 22 -d' ') # Process running ticks
            PID_START_TIME_SECS=$(($PID_START_TIME_TICKS / 100)) # Assuming 100 jiffies per second
            CLC_TCK=$(getconf CLK_TCK)
            PID_UTIME_TICKS=$(echo $STAT_DATA | cut -f 14 -d " ")
            PID_STIME_TICKS=$(echo $STAT_DATA | cut -f 15 -d " ")

            # CPU usage calculation
            if (( CPU_SYS_ST_SEC - PID_START_TIME_SECS > 0 )); then
                CPU=$(echo "scale=2; (($PID_UTIME_TICKS + $PID_STIME_TICKS) * 100 / $CLC_TCK) / ($CPU_SYS_ST_SEC - $PID_START_TIME_SECS)" | bc | awk '{printf "%.3f", $0 }')
            else
                CPU=0.0
            fi

            memtotal=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
            if (( memtotal > 0 )); then
                mem_usage=$(echo "scale=2; ($rsssize / $memtotal) * 100" | bc | awk '{printf "%.2f", $0 }')
            else
                mem_usage=0.0
            fi
            
            if [[ "$tty" != "pipe"* ]]; then
                # Calculate start time
                start_time_formatted=$(date -d "@$(( $(date +%s) - (CPU_SYS_ST_SEC - PID_START_TIME_SECS) ))" "+%H:%M")
                
                # Get user and system time in jiffies for formatted time
                time=$(awk '{print $14 + $15}' "/proc/$pid/stat") # User + system time in jiffies
                uTime=$(echo "scale=2; $time/100" | bc) # Assuming 100 jiffies per second
                int=$(printf "%.0f" "$uTime")
                formatted_time=$(date -u --date="@$int" | cut -f 5 -d " ")

                echo -e "$USER\t$pid\t$CPU\t$mem_usage\t$vmsize\t$rsssize\t$tty\t$start_time_formatted\t$formatted_time\t$cmd"
            fi
        fi
    done
}

# Main logic to handle command-line arguments
if [ $# -eq 0 ]; then
    # No arguments provided
    case_no_argument
elif [ "$1" == "-p" ]; then
    # -p argument provided
    shift  # Remove the -p argument
    case_pid_argument "$@"
elif [ "$1" == "-a" ]; then
    # -a argument provided
    case_all_processes
elif [ "$1" == "-u" ]; then
    # -u argument provided
    case_user_processes
fi