#!/bin/bash
# Color codes
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
RESET="\e[0m"

#defining variables
running_count=0
total_kernel_threads=0
taskcounter=0
threads=0

# Default values
user_sleep=2
pid_filter=""

# case statements
while getopts "d:p:" opt; do
    case $opt in
        d) 
            if [[ $OPTARG =~ ^[0-9]+$ ]]; then  # Check if the argument is a number
                user_sleep=$OPTARG 
            else
                echo "Error: Argument for -d must be a positive integer." 
                exit 1
            fi
            ;;
        p) pid_filter=$OPTARG ;;
        *) echo "Usage: $0 [-d sleep_duration] [-p pid]" ; exit 1 ;;
    esac
done

# Function to display the process information
display_process_info() {
    local pid_filter=$@
    # Prepare an array to hold process information
    process_info=()

    # Get total memory from /proc/meminfo
    total_mem=$(awk '/MemTotal/{print $2}' /proc/meminfo)

    # Loop through the /proc directory to gather process information
    for pid in /proc/[0-9]*; do
        if [ -d "$pid" ]; then
            stat=$(<"$pid/stat")
            # Get process details
            cmd=$(tr '\0' ' ' < "$pid/cmdline")
            cmd_name=$(echo "$cmd" | awk '{print $1}')
            vsz=$(cat "$pid/stat" 2>/dev/null | cut -f 23 -d " ")
            vsz=$(echo "scale=0; $vsz/1024" | bc)

            # Check if stat is empty
            if [ -z "$stat" ]; then
                continue
            fi

            # Extract relevant information from stat and status files
            if [ -n "$vsz" ]; then
                vszsize=$(($vsz * 4))
            fi
            ni=$(awk '{print $19}' "$pid/stat" 2>/dev/null)
            utime=$(echo $stat | awk '{print $14}')
            stime=$(echo $stat | awk '{print $15}')
            rsssize=$(awk '{print $2}' $pid/statm)
            rss_size=$(($rsssize * 4))
            CPU_SYS_ST_SEC=$(awk '{print $1}' /proc/uptime)
            PID_START_TIME_TICKS=$(echo $stat | awk '{print $22}') # a process running ticks
            PID_START_TIME_SECS=$(($PID_START_TIME_TICKS / 100))
            CLC_TCK=$(getconf CLK_TCK)
            PID_UTIME_TICKS=$(echo $stat | awk '{print $14}')
            PID_STIME_TICKS=$(echo $stat | awk '{print $15}')

            # Calculate CPU usage
            CPU=$(echo "scale=2; (($PID_UTIME_TICKS + $PID_STIME_TICKS) * 100 / $CLC_TCK) / ($CPU_SYS_ST_SEC - $PID_START_TIME_SECS)" | bc | awk '{printf "%.3f", $0 }')

            # Calculate total time in seconds
            total_time=$((utime + stime))
            total_time=$((total_time / 100))  # Convert to seconds
            time=$(printf "%02d:%02d:%02d" $((total_time / 3600)) $(( (total_time % 3600) / 60 )) $((total_time % 60)))

            # Calculate %MEM
            memtotal=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
            MEM=$(echo "scale=2; ($rss_size/$memtotal) * 100" | bc)
            MEM=$(printf "%.3f" "$MEM")
            
            # Get priority (PR) from the stat file
            pr=$(echo "$stat" | awk '{print $18}')
            uid=$(awk '/^Uid:/{print $2}' "$pid/status" 2>/dev/null)
            user=$(getent passwd "$uid" | cut -d: -f1)  # Get username from UID
            SHR_PAGES=$(cat $pid/statm | awk '{print $3}')
            SHR=$(($SHR_PAGES * 4))

            # Get just the numeric PID
            pid_number="${pid##*/}"

            state=$(awk '{print $3}' $pid/stat)

            # Only include the process if pid_filter is empty or matches the current PID
            if [ -z "$pid_filter" ] || [ "$pid_number" == "$pid_filter" ]; then
                # Store the process information in the array
                process_info+=("$user $pid_number $vsz $ni $CPU $MEM $pr $state $time $rss_size $SHR $cmd_name")
            fi
        fi
    done

    smso=$(tput smso)
    rmso=$(tput rmso)

    # Print the process information 
    output=$(printf "%s%-15s %-10s %-10s %-12s %-8s %-8s %-5s %-5s %-7s %-10s %-10s %s%s\n" "$smso" "USER" "PID" "VIRT" "NI" "%CPU" "%MEM" "PR" "S" "TIME+" "RSS" "SHR" "COMMAND" "$rmso")
    output+="\n-----------------------------------------------------------------------------------------------------------------------------------\n"
    output+=$(printf "%s\n" "${process_info[@]}" | sort -k5,5nr | head -n 20 | awk '{printf "%-15s %-10s %-10s %-12s %-8s %-8s %-5s %-5s %-7s %-10s %-10s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12}')
    output+="\n-----------------------------------------------------------------------------------------------------------------------------------\n"
    output+="Press 'q' to quit."

    echo -e "$output"
}

# Function to calculate CPU usage percentage for a given core
get_cpu_usage_snapshot() {
    local core=$1
    local stats1=($(grep "^$core " /proc/stat))
    
    # Read the first snapshot
    local user1=${stats1[1]}
    local nice1=${stats1[2]}
    local system1=${stats1[3]}
    local idle1=${stats1[4]}
    local iowait1=${stats1[5]}
    local irq1=${stats1[6]}
    local softirq1=${stats1[7]}

    # Wait for user-defined seconds before taking the second snapshot
    sleep $user_sleep

    # Read the second snapshot
    local stats2=($(grep "^$core " /proc/stat))
    local user2=${stats2[1]}
    local nice2=${stats2[2]}
    local system2=${stats2[3]}
    local idle2=${stats2[4]}
    local iowait2=${stats2[5]}
    local irq2=${stats2[6]}
    local softirq2=${stats2[7]}

    # Calculate the differences between the two snapshots
    local user_diff=$((user2 - user1))
    local nice_diff=$((nice2 - nice1))
    local system_diff=$((system2 - system1))
    local idle_diff=$((idle2 - idle1))
    local iowait_diff=$((iowait2 - iowait1))
    local irq_diff=$((irq2 - irq1))
    local softirq_diff=$((softirq2 - softirq1))

    # Total time difference
    local total_diff=$((user_diff + nice_diff + system_diff + idle_diff + iowait_diff + irq_diff + softirq_diff))

    # Active time difference
    local active_diff=$((user_diff + nice_diff + system_diff + iowait_diff + irq_diff + softirq_diff))

    # Calculate CPU usage percentage
    local usage_percentage=$((100 * active_diff / total_diff))

    # Return the CPU usage percentage
    echo $usage_percentage
}

# Function to print the graph based on the usage percentage
print_graph() {
    local usage=$1
    local max_length=50  # Maximum length of the graph in terms of number of '#'

    # Calculate the number of '#' characters for the graph based on usage
    local hash_count=$((usage * max_length / 100))  # Scale the usage to fit in the graph

    # Determine color based on usage percentage
    local color
    if (( usage < 20 )); then
        color="\e[34m"  # Blue
    elif (( usage < 40 )); then
        color="\e[32m"  # Green
    elif (( usage < 60 )); then
        color="\e[31m"  # Red
    else
        color="\e[34m"  # Blue
    fi

    # Print the graph in the requested format
    printf "%3d%% [ " $usage
    for ((i=0; i<hash_count; i++)); do
        printf "${color}|"
    done
    echo -e "\e[0m ]"  # Reset to default color
}

stat() {
    for pid in /proc/[0-9]*; do
        # Check if the process directory exists
        if [ -d "$pid" ]; then
            # Read the state from /proc/<pid>/stat
            state=$(awk '{print $3}' "$pid/stat")

            # Increment the running task counter if the state is 'R' (running)
            if [ "$state" == "R" ]; then
                running_count=$((running_count + 1))
            fi

            # Read the command line
            cmdline=$(tr '\0' ' ' < "$pid/cmdline")
            rsssize=$(awk '{print $2}' $pid/statm)
            if [ "$rsssize" != "0" ]; then
                taskcounter=$((taskcounter+1))
                threads=$((threads+$(ls $pid/task | wc -l )))
            fi
            # A kernel thread usually has an empty cmdline and is not a zombie (state 'Z')
            if [[ -z "$cmdline" && "$state" != "Z" ]]; then
                total_kernel_threads=$((total_kernel_threads + 1))
            fi
        fi
    done
    echo "Number of running tasks: $running_count"

    # Output the total count of kernel threads
    echo "Total number of kernel threads: $total_kernel_threads"

    # Get uptime in seconds and format it
    uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
    printf "Uptime: %02d:%02d:%02d\n" $((uptime_seconds/3600)) $(((uptime_seconds%3600)/60)) $((uptime_seconds%60))

    # Load average values
    read load1 load5 load15 < <(awk '{print $1, $2, $3}' /proc/loadavg)
    printf "Load Average: %.2f, %.2f, %.2f\n" "$load1" "$load5" "$load15"
    echo "Tasks: $taskcounter"
    echo "Threads: $threads"
}

# Main loop to periodically update the CPU usage graphs and process information
while true; do
    clear
    echo -e "CPU Usage (Updated Every $user_sleep Seconds)"
    # Process each CPU (cpu0, cpu1, cpu2, ..., cpuX)
    for core in $(grep -oP '^cpu[0-9]+' /proc/stat | sort); do
        # Get the CPU usage for this core by calculating the difference between two time snapshots
        usage=$(get_cpu_usage_snapshot $core)

        # Print the graph for this core
        printf "%s " "$core"  # Print core label (cpu0, cpu1, etc.)
        print_graph $usage  # Print the graph for the current CPU
        printf "\r"  # Move the cursor back to the beginning of the line (to overwrite the graph)
    done

    # Wait for user-defined seconds before updating the graph again
    sleep $user_sleep
    # Now display system statistics
    stat
    echo -e "\n${GREEN}Processes by CPU Usage:${GREEN}"
    display_process_info "$pid_filter"  # Pass the PID argument to the function
    sleep $user_sleep
    taskcounter=0  
    threads=0
    # Check for user input to quit
    read -t 2 -n 1 key
    if [[ $key = "q" ]]; then
        echo -e "\nExiting the monitoring."
        break
    fi
done