#!/bin/bash

# Function to display system information
display_system_info() {
    current_time=$(date +"%H:%M:%S")
    uptime_info=$(uptime -p | sed 's/up //')
    users=$(who | wc -l)
    load_avg=$(cat /proc/loadavg | awk '{print $1, $2, $3}')

    # Defining the variables
    total_tasks=0
    running_tasks=0
    sleeping_tasks=0
    stopped_tasks=0
    zombie_tasks=0

    # Getting the state of all the tasks
    for pid in /proc/[0-9]*; do
        if [ -f "$pid/stat" ]; then
            total_tasks=$((total_tasks + 1))
            state=$(awk '{print $3}' "$pid/stat")
            case "$state" in
                R) running_tasks=$((running_tasks + 1)) ;;
                S) sleeping_tasks=$((sleeping_tasks + 1)) ;;
                T) stopped_tasks=$((stopped_tasks + 1)) ;;
                Z) zombie_tasks=$((zombie_tasks + 1)) ;;
            esac
        fi
    done

    # Get memory info
    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2/1024}' | xargs printf "%.1f MiB" ) # getting all the values from the meminfo file in /proc directory
    mem_free=$(grep MemFree /proc/meminfo | awk '{print $2/1024}' | xargs printf "%.1f MiB" )
    mem_used=$(echo "$mem_total - $mem_free" | bc 2>/dev/null | xargs printf "%.1f")
    mem_buffers=$(grep Buffers /proc/meminfo | awk '{print $2/1024}' | xargs printf "%.1f")
    mem_cached=$(grep Cached /proc/meminfo | awk '{print $2/1024}' | xargs printf "%.1f")
    mem_bufcach=$(echo "$mem_buffers + $mem_cached" | bc 2>/dev/null | xargs printf "%.1f")
    swap_total=$(grep SwapTotal /proc/meminfo | awk '{print $2/1024}' | xargs printf "%.1f")
    swap_free=$(grep SwapFree /proc/meminfo | awk '{print $2/1024}' | xargs printf "%.1f")

    echo "top - $current_time up $uptime_info,  $users users,  load average: $load_avg"
    echo "Tasks: $total_tasks total, $running_tasks running, $sleeping_tasks sleeping, $stopped_tasks stopped, $zombie_tasks zombie"
    echo "MiB Mem: $mem_total total, $mem_free free, $mem_used used, $mem_bufcach MiB buff/cache"
    echo "MiB Swap: $swap_total total, $swap_free free"
}

# Function to gather process information
gather_process_info() {
    local pid=$1
    local process_info=()

    # Get total memory from /proc/meminfo
    total_mem=$(awk '/MemTotal/{print $2}' /proc/meminfo)

    if [ -d "/proc/$pid" ]; then
        stat=$(<"/proc/$pid/stat")
        cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline")
        cmd_name=$(echo "$cmd" | awk '{print $1}')
        
        # Check if stat is empty
        if [ -z "$stat" ]; then
            return
        fi

        vsz=$(awk '{print $23}' "/proc/$pid/stat" 2>/dev/null)
        vsz=$(echo "scale=0; $vsz/1024" | bc)
        ni=$(awk '{print $19}' "/proc/$pid/stat" 2>/dev/null)
        utime=$(echo $stat | awk '{print $14}')
        stime=$(echo $stat | awk '{print $15}')
        rsssize=$(awk '{print $2}' /proc/$pid/statm)
        rss_size=$(($rsssize * 4))

        # Get the total CPU time since system boot
        CPU_SYS_ST_SEC=$(awk '{print $1}' /proc/uptime)
        PID_START_TIME_TICKS=$(echo $stat | awk '{print $22}') # a process running ticks
        PID_START_TIME_SECS=$(($PID_START_TIME_TICKS / 100))
        CLC_TCK=$(getconf CLK_TCK)
        PID_UTIME_TICKS=$(echo $stat | awk '{print $14}')
        PID_STIME_TICKS=$(echo $stat | awk '{print $15}')
    fi
}

# Function to gather process information
gather_process_info() {
    local pid=$1
    local process_info=()

    # Get total memory from /proc/meminfo
    total_mem=$(awk '/MemTotal/{print $2}' /proc/meminfo)

    if [ -d "/proc/$pid" ]; then
        stat=$(<"/proc/$pid/stat")
        cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline")
        cmd_name=$(echo "$cmd" | awk '{print $1}')
        
        # Check if stat is empty
        if [ -z "$stat" ]; then
            return
        fi

        vsz=$(awk '{print $23}' "/proc/$pid/stat" 2>/dev/null)
        vsz=$(echo "scale=0; $vsz/1024" | bc)
        ni=$(awk '{print $19}' "/proc/$pid/stat" 2>/dev/null)
        utime=$(echo $stat | awk '{print $14}')
        stime=$(echo $stat | awk '{print $15}')
        rsssize=$(awk '{print $2}' /proc/$pid/statm)
        rss_size=$(($rsssize * 4))

        # Get the total CPU time since system boot
        CPU_SYS_ST_SEC=$(awk '{print $1}' /proc/uptime)
        PID_START_TIME_TICKS=$(echo $stat | awk '{print $22}') # a process running ticks
        PID_START_TIME_SECS=$(($PID_START_TIME_TICKS / 100))
        CLC_TCK=$(getconf CLK_TCK)
        PID_UTIME_TICKS=$(echo $stat | awk '{print $14}')
        PID_STIME_TICKS=$(echo $stat | awk '{print $15}')

        # Calculate CPU usage
        CPU=$(echo "scale=2; (($PID_UTIME_TICKS + $PID_STIME_TICKS) * 100 / $CLC_TCK) / ($CPU_SYS_ST_SEC - $PID_START_TIME_SECS)" | bc | awk '{printf "%.2f", $0 }')

        # Calculate total time in seconds
        total_time=$((utime + stime))
        total_time=$((total_time / 100))  # Convert to seconds
        time=$(printf "%02d:%02d:%02d" $((total_time / 3600)) $(( (total_time % 3600) / 60 )) $((total_time % 60)))

        # Calculate %MEM
        MEM=$(echo "scale=2; ($rss_size/$total_mem) * 100" | bc)
        MEM=$(printf "%.2f" "$MEM")

        # Get priority (PR) from the stat file
        pr=$(echo "$stat" | awk '{print $18}')
        uid=$(awk '/^Uid:/{print $2}' "/proc/$pid/status" 2>/dev/null)
        user=$(getent passwd "$uid" | cut -d: -f1)  # Get username from UID

        SHR_PAGES=$(cat /proc/$pid/statm | awk '{print $3}')
        SHR=$(($SHR_PAGES * 4))

        # Get just the numeric PID
        pid_number="${pid##*/}"

        state=$(echo "$stat" | awk '{print $3}')  # Get process state

        # Store the process information in the array
        process_info+=("$user $pid_number $vsz $ni $CPU $MEM $pr $state $time $rss_size $SHR $cmd_name")
    fi

    echo "${process_info[@]}"
}

# Function to display process information
display_process_info() {
    smso=$(tput smso)
    rmso=$(tput rmso)

    # Print the process information header
    printf "%s%-15s %-10s %-10s %-12s %-8s %-8s %-5s %-5s %-7s %-10s %-10s %s%s\n" "$smso" "USER" "PID" "VIRT (MB)" "NI" "%CPU" "%MEM" "PR" "S" "TIME+" "RSS (KB)" "SHR" "COMMAND" "$rmso"

    # Function to display the process information for a specific user
    display_process_info() {
        printf "%s%-15s %-10s %-10s %-12s %-8s %-8s %-5s %-5s %-7s %-10s %-10s %s%s\n" "$smso" "USER" "PID" "VIRT (MB)" "NI" "%CPU" "%MEM" "PR" "S" "TIME+" "RSS (KB)" "SHR" "COMMAND" "$rmso"
        local user_arg=$1

        # Print the header for user-specific processes
        echo "Process information for User: $user_arg"
        echo "-------------------------------------------------------------------------------------"

        # Get total memory from /proc/meminfo
        total_mem=$(awk '/MemTotal/{print $2}' /proc/meminfo)

        # Loop through all PIDs in /proc
        for pid in /proc/[0-9]*; do
            pid=${pid##*/}  # Extract just the PID number

            # Get the UID of the process owner
            uid=$(awk '/^Uid:/{print $2}' "/proc/$pid/status" 2>/dev/null)

            # Get the username corresponding to the UID
            user=$(getent passwd "$uid" | cut -d: -f1)

            # Only display if the username matches the provided argument
            if [ "$user" == "$user_arg" ]; then
                # Get process details
                cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline")
                cmd_name=$(echo "$cmd" | awk '{print $1}')

                # Check if stat is empty
                stat=$(<"/proc/$pid/stat")
                if [ -z "$stat" ]; then
                    continue
                fi

                # Extract relevant information from stat and status files
                vsz=$(awk '{print $23}' "/proc/$pid/stat" 2>/dev/null)
                vsz=$(echo "scale=0; $vsz/1024" | bc)  # Convert to MB
                ni=$(awk '{print $19}' "/proc/$pid/stat" 2>/dev/null)
                utime=$(echo $stat | awk '{print $14}')
                stime=$(echo $stat | awk '{print $15}')
                rsssize=$(awk '{print $2}' /proc/$pid/statm)
                rss_size=$(($rsssize * 4))  # Convert pages to KB

                # Get the total CPU time since system boot
                CPU_SYS_ST_SEC=$(awk '{print $1}' /proc/uptime)
                PID_START_TIME_TICKS=$(echo $stat | awk '{print $22}') # a process running ticks
                PID_START_TIME_SECS=$(($PID_START_TIME_TICKS / 100))
                CLC_TCK=$(getconf CLK_TCK)
                PID_UTIME_TICKS=$(echo $stat | awk '{print $14}')
                PID_STIME_TICKS=$(echo $stat | awk '{print $15}')

                # Calculate CPU usage
                CPU=$(echo "scale=2; (($PID_UTIME_TICKS + $PID_STIME_TICKS) * 100 / $CLC_TCK) / ($CPU_SYS_ST_SEC - $PID_START_TIME_SECS)" | bc | awk '{printf "%.2f", $0 }')

                # Calculate total time in seconds
                total_time=$((utime + stime))
                total_time=$((total_time / 100))  # Convert to seconds
                time=$(printf "%02d:%02d:%02d" $((total_time / 3600)) $(( (total_time % 3600) / 60 )) $((total_time % 60)))

                # Calculate %MEM
                MEM=$(echo "scale=2; ($rss_size/$total_mem) * 100" | bc)
                MEM=$(printf "%.2f" "$MEM")

                # Get priority (PR) from the stat file
                pr=$(echo "$stat" | awk '{print $18}')
                state=$(echo "$stat" | awk '{print $3}')  # Get process state

                # Print the process information with better formatting
                printf "%-15s %-10s %-10s %-12s %-8s %-8s %-5s %-5s %-7s %-10s %-10s %s\n" "$user" "$pid" "$vsz" "$ni" "$CPU " "$MEM" "$pr" "$state" "$time" "$rss_size" "$cmd_name"
            fi
        done

        echo "-------------------------------------------------------------------------------------"
    }

    # Check if a username argument is provided
    if [ $# -eq 0 ]; then
        echo "Usage: $0 <username>"
        exit 1
    fi

    # Get the username from the first argument
    user_arg=$1

    # Display process information for the given user
    while true; do
        clear
        header
        display_process_info "$user_arg"
        sleep 2
    done
}

# Function to display process information for a specific PID

display_process_info_pid() {
    local pid=$1

    # Get the process information
    local process_info
    process_info=($(gather_process_info "$pid"))

    # Check if process_info is empty
    if [ ${#process_info[@]} -eq 0 ]; then
        echo "No information available for PID: $pid"
        return
    fi

    # Print the process information
    printf "%-15s %-10s %-10s %-12s %-8s %-8s %-5s %-5s %-7s %-10s %-10s %s\n" "${process_info[@]}"
}
# Main logic to handle command-line arguments
if [ $# -eq 0 ]; then
    # No arguments provided
    while true; do
        clear
        display_system_info
        smso=$(tput smso)
        rmso=$(tput rmso)
        printf "%s%-15s %-10s %-10s %-12s %-8s %-8s %-5s %-5s %-7s %-10s %-10s %s%s\n" "$smso" "USER" "PID" "VIRT" "NI" "%CPU" "%MEM" "PR" "S" "TIME+" "RSS" "SHR" "COMMAND" "$rmso"
        printf "%s\n" "$(for pid in /proc/[0-9]*; do gather_process_info "${pid##*/}"; done)" | sort -k5,5nr | head -n 20 | awk '{printf "%-15s %-10s %-10s %-12s %-8s %-8s %-5s %-5s %-7s %-10s %-10s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12}'
        sleep 5
        read -t 0.5 -n 1 key
        if [[ $key = "q" ]]; then
            echo "Exiting the process monitoring."
            break
        fi
    done
elif [ "$1" == "-p" ]; then
    # -p argument provided
    if [ -z "$2" ]; then
        echo "Usage: $0 -p <PID1> <PID2> ... <PIDN>"
        exit 1
    fi
    display_system_info

    # Loop through all provided PIDs
    while true; do
        clear
        # Print the header
        smso=$(tput smso)
        rmso=$(tput rmso)
        display_system_info
        printf "%s%-15s %-10s %-10s %-12s %-8s %-8s %-5s %-5s %-7s %-10s %-10s %s%s\n" "$smso" "USER" "PID" "VIRT" "NI" "%CPU" "%MEM" "PR" "S" "TIME+" "RSS" "SHR" "COMMAND" "$rmso"
        # Loop through all provided PIDs again for continuous monitoring
        for pid in "${@:2}"; do
            display_process_info_pid "$pid"
        done
        sleep 2
        read -t 0.5 -n 1 key
        if [[ $key = "q" ]]; then
            echo "Exiting the process monitoring."
            break
        fi
    done

elif [ "$1" == "-d" ]; then
    if [ -z "$2" ]; then
        echo "Usage: $0 -d <delaytime>"
        exit 1
    fi
    while true; do
        clear
        display_system_info
        smso=$(tput smso)
        rmso=$(tput rmso)
        printf "%s%-15s %-10s %-10s %-12s %-8s %-8s %-5s %-5s %-7s %-10s %-10s %s%s\n" "$smso" "USER" "PID" "VIRT" "NI" "%CPU" "%MEM" "PR" "S" "TIME+" "RSS" "SHR" "COMMAND" "$rmso"
        printf "%s\n" "$(for pid in /proc/[0-9]*; do gather_process_info "${pid##*/}"; done)" | sort -k5,5nr | head -n 20 | awk '{printf "%-15s %-10s %-10s %-12s %-8s %-8s %-5s %-5s %-7s %-10s %-10s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12}'
        sleep "$2"
        read -t 2 -n 1 key
        if [[ $key = "q" ]]; then
            echo "Exiting the process monitoring."
            break
        fi
    done
elif [ "$1" == "-U" ]; then
    if [ -z "$2" ]; then
        echo "Usage: $0 -d <delaytime>"
        exit 1
    fi
    while true; do
        clear
        display_system_info
        display_process_info "$2"
        sleep 4
    done
fi