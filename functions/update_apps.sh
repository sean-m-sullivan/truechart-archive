#!/bin/bash


commander(){
mapfile -t array < <(cli -m csv -c 'app chart_release query name,update_available,human_version,human_latest_version,container_images_update_available,status' | tr -d " \t\r" | grep -E ",true($|,)" | sort)
echo -e "🅄 🄿 🄳 🄰 🅃 🄴 🅂"
[[ -z ${array[*]} ]] && echo "There are no updates available" && echo -e "\n" && return 0 || echo "Update(s) Available: ${#array[@]}"
echo "Asynchronous Updates: $update_limit"
[[ -z $timeout ]] && echo "Default Timeout: 500" && timeout=500 || echo "Custom Timeout: $timeout"
[[ "$timeout" -le 120 ]] && echo "Warning: Your timeout is set low and may lead to premature rollbacks or skips"

# previous 20% 2 min 9 seconds
# it=0
# while_status=$(cli -m csv -c 'app chart_release query name,update_available,human_version,human_latest_version,status' 2>/dev/null)
# echo "$while_status" > temp.txt
# rm trigger &>/dev/null
# delay=2
# final_check=0
# while true
# do
#     if [[ -f trigger ]]; then
#         delay=4
#         if while_status=$(cli -m csv -c 'app chart_release query name,update_available,human_version,human_latest_version,status' 2>/dev/null) ; then
#             echo "$while_status" > temp.txt
#         else
#             echo "Middlewared timed out. Consider setting a lower number for async applications"
#             continue
#         fi
#     fi
#     proc_count=${#processes[@]}
#     count=0
#     for proc in "${processes[@]}"
#     do
#         kill -0 "$proc" &> /dev/null || { unset "processes[$count]"; ((proc_count--)); }
#         ((count++)) 
#     done
#     if [[ "$proc_count" -ge "$update_limit" ]]; then
#         sleep $delay
#     elif [[ $it -lt ${#array[@]} ]]; then
#         until [[ "$proc_count" -ge "$update_limit" || $it -ge ${#array[@]} ]]
#         do
#             update_apps "${array[$it]}" &
#             processes+=($!)
#             sleep 4
#             ((it++))
#             ((proc_count++))
#         done
#     elif [[ $proc_count != 0 ]]; then # Wait for all processes to finish
#         sleep $delay
#     else # All processes must be completed, break out of loop
#         [[ $final_check == 0 ]] && ((final_check++)) && continue
#         break
#     fi
# done
# rm temp.txt
# [[ -f trigger ]] && rm trigger
# echo
# echo

it=0
while_count=0
while true
do
    if while_status=$(cli -m csv -c 'app chart_release query name,update_available,human_version,human_latest_version,status' 2>/dev/null) ; then
        ((while_count++))
        echo -e "$while_count\n$while_status" > temp.txt
    else
        echo "Middlewared timed out. Consider setting a lower number for async applications"
        continue
    fi
    proc_count=${#processes[@]}
    count=0
    for proc in "${processes[@]}"
    do
        kill -0 "$proc" &> /dev/null || { unset "processes[$count]"; ((proc_count--)); }
        ((count++)) 
    done
    if [[ "$proc_count" -ge "$update_limit" ]]; then
        sleep 3
    elif [[ $it -lt ${#array[@]} ]]; then
        # loop=0
        # until [[ $loop -ge 2 || $it -ge ${#array[@]} ]];
        # do
        update_apps "${array[$it]}" &
        processes+=($!)
        ((loop++))
        ((it++))
        # done
    elif [[ $proc_count != 0 ]]; then # Wait for all processes to finish
        sleep 3
    else # All processes must be completed, break out of loop
        break
    fi
done
rm temp.txt
echo
echo

}
export -f commander


update_apps(){
app_name=$(echo "${array[$it]}" | awk -F ',' '{print $1}') #print out first catagory, name.
printf '%s\0' "${ignore[@]}" | grep -iFxqz "${app_name}" && echo -e "\n$app_name\nIgnored, skipping" && return 0 #If application is on ignore list, skip
old_app_ver=$(echo "${array[$it]}" | awk -F ',' '{print $4}' | awk -F '_' '{print $1}' | awk -F '.' '{print $1}') #previous/current Application MAJOR Version
new_app_ver=$(echo "${array[$it]}" | awk -F ',' '{print $5}' | awk -F '_' '{print $1}' | awk -F '.' '{print $1}') #new Application MAJOR Version
old_chart_ver=$(echo "${array[$it]}" | awk -F ',' '{print $4}' | awk -F '_' '{print $2}' | awk -F '.' '{print $1}') # Old Chart MAJOR version
new_chart_ver=$(echo "${array[$it]}" | awk -F ',' '{print $5}' | awk -F '_' '{print $2}' | awk -F '.' '{print $1}') # New Chart MAJOR version
startstatus=$(echo "${array[$it]}" | awk -F ',' '{print $2}') #status of the app: STOPPED / DEPLOYING / ACTIVE
diff_app=$(diff <(echo "$old_app_ver") <(echo "$new_app_ver")) #caluclating difference in major app versions
diff_chart=$(diff <(echo "$old_chart_ver") <(echo "$new_chart_ver")) #caluclating difference in Chart versions
old_full_ver=$(echo "${array[$it]}" | awk -F ',' '{print $4}') #Upgraded From
new_full_ver=$(echo "${array[$it]}" | awk -F ',' '{print $5}') #Upraded To
rollback_version=$(echo "${array[$it]}" | awk -F ',' '{print $4}' | awk -F '_' '{print $2}')
if  grep -qs "^$app_name," failed.txt ; then
    failed_ver=$(grep "^$app_name," failed.txt | awk -F ',' '{print $2}')
    if [[ "$failed_ver" == "$new_full_ver" ]] ; then
        echo -e "\n$app_name"
        echo -e "Skipping previously failed version:\n$new_full_ver"
        return 0
    else 
        sed -i /"$app_name",/d failed.txt
    fi
fi
if [[ "$diff_app" == "$diff_chart" || "$update_all_apps" == "true" ]]; then #continue to update
    if [[ $stop_before_update == "true" ]]; then # Check to see if user is using -S or not
        if [[ "$startstatus" ==  "STOPPED" ]]; then # if status is already stopped, skip while loop
            echo_array+=("\n$app_name")
            [[ "$verbose" == "true" ]] && echo_array+=("Updating..")
            if update ;then
                echo_array+=("Updated\n$old_full_ver\n$new_full_ver")
            else
                echo_array+=("Failed to update")
                return
            fi
        else # if status was not STOPPED, stop the app prior to updating
            echo_array+=("\n$app_name")
            [[ "$verbose" == "true" ]] && echo_array+=("Stopping prior to update..")
            midclt call chart.release.scale "$app_name" '{"replica_count": 0}' &> /dev/null || echo_array+=("Error: Failed to stop $app_name")
            SECONDS=0
            # [[ ! -e trigger ]] && touch trigger
            while [[ "$status" !=  "STOPPED" ]]
            do
                status=$( grep "^$app_name," temp.txt | awk -F ',' '{print $2}')
                if [[ "$status"  ==  "STOPPED" ]]; then
                    echo_array+=("Stopped")
                    [[ "$verbose" == "true" ]] && echo_array+=("Updating..")
                    if update ;then
                        echo_array+=("Updated\n$old_full_ver\n$new_full_ver")
                    else
                        echo_array+=("Failed to update")
                        return
                    fi
                elif [[ "$SECONDS" -ge "$timeout" ]]; then
                    echo_array+=("Error: Run Time($SECONDS) has exceeded Timeout($timeout)")
                    break
                elif [[ "$status" !=  "STOPPED" ]]; then
                    [[ "$verbose" == "true" ]] && echo_array+=("Waiting $((timeout-SECONDS)) more seconds for $app_name to be STOPPED")
                    sleep 5
                fi
            done
        fi
    else #user must not be using -S, just update
        echo_array+=("\n$app_name")
        [[ "$verbose" == "true" ]] && echo_array+=("Updating..")
        if update ;then
            echo_array+=("Updated\n$old_full_ver\n$new_full_ver")
        else
            echo_array+=("Failed to update")
            return
        fi
    fi
else
    echo -e "\n$app_name\nMajor Release, update manually"
    return 0
fi
after_update_actions
}
export -f update_apps


update(){
count=0
while [[ $count -lt 3 ]]
do
    update_avail=$(grep "^$app_name," temp.txt | awk -F ',' '{print $3}')
    if [[ $update_avail == "true" ]]; then
        if ! cli -c 'app chart_release upgrade release_name=''"'"$app_name"'"' &> /dev/null ; then
            # [[ ! -e trigger ]] && touch trigger && sleep 10
            sleep 6
            ((count++))
            continue
        fi
        break
    elif [[ $update_avail == "false" ]]; then
        break
    else
        ((count++))
        sleep 6
    fi
done
}
export -f update

after_update_actions(){
SECONDS=0
count=0
if [[ $rollback == "true" || "$startstatus"  ==  "STOPPED" ]]; then
    # [[ ! -e trigger ]] && touch trigger && sleep 10
    while true
    do
    if [[ $count -lt 1 ]]; then
            old_status=$(grep "^$app_name," temp.txt)
        else
            before_loop=$(head -n 1 temp.txt)
            new_status=$old_status
            until [[ "$new_status" != "$old_status" || $current_loop -gt 3 ]] # Wait for a change in the file BEFORE continuing
            do
                new_status=$(grep "^$app_name," temp.txt)
                sleep 1
                if ! echo -e "$(head -n 1 temp.txt)" | grep -qs ^"$before_loop" ; then
                    before_loop=$(head -n 1 temp.txt)
                    ((current_loop++))
                fi
            done
            old_status=$new_status
        fi

        # if [[ $count -lt 1 ]]; then
        #     while_count=$(head -n 1 temp.txt)
        # else
        #     until [[ $while_count -lt $current_count ]] # Wait for a change in the file BEFORE continuing
        #     do
        #         current_count=$(head -n 1 temp.txt)
        #         sleep 1
        #     done
        #     while_count=$current_count
        # fi
        status=$( grep "^$app_name," temp.txt | awk -F ',' '{print $2}')
        (( count++ ))
        if [[ "$status"  ==  "ACTIVE" ]]; then
            if [[ "$startstatus"  ==  "STOPPED" ]]; then
                [[ "$count" -le 1 && "$verbose" == "true"  ]] && echo_array+=("Verifying Active..") && continue #if reports active on FIRST time through loop, double check
                [[ "$count" -le 1  && -z "$verbose" ]] &&  continue #if reports active on FIRST time through loop, double check
                [[ "$verbose" == "true" ]] && echo_array+=("Returing to STOPPED state..")
                midclt call chart.release.scale "$app_name" '{"replica_count": 0}' &> /dev/null || { echo_array+=("Error: Failed to stop $app_name") ; break ; }
                echo_array+=("Stopped")
                break
            else
                [[ "$count" -le 1 && "$verbose" == "true"  ]] && echo_array+=("Verifying Active..") && continue #if reports active on FIRST time through loop, double check
                [[ "$count" -le 1  && -z "$verbose" ]] &&  continue #if reports active on FIRST time through loop, double check
                echo_array+=("Active")
                break #if reports active any time after the first loop, assume actually active.
            fi
        elif [[ "$status"  ==  "STOPPED" ]]; then
            [[ "$count" -le 1 && "$verbose" == "true"  ]] && echo_array+=("Verifying Stopped..") && continue #if reports stopped on FIRST time through loop, double check
            [[ "$count" -le 1  && -z "$verbose" ]] &&  continue #if reports stopped on FIRST time through loop, double check
            echo_array+=("Stopped")
            break #if reports stopped any time after the first loop, assume its extermal services.
        elif [[ "$SECONDS" -ge "$timeout" && "$status" == "DEPLOYING" ]]; then
            if [[ $rollback == "true" ]]; then
                if [[ "$failed" != "true" ]]; then
                    echo_array+=("Error: Run Time($SECONDS) for $app_name has exceeded Timeout($timeout)")
                    echo_array+=("If this is a slow starting application, set a higher timeout with -t")
                    echo_array+=("If this applicaion is always DEPLOYING, you can disable all probes under the Healthcheck Probes Liveness section in the edit configuration")
                    echo_array+=("Reverting update..")
                    midclt call chart.release.rollback "$app_name" "{\"item_version\": \"$rollback_version\"}" &> /dev/null || { echo_array+=("Error: Failed to rollback $app_name") ; break ; }
                    [[ "$startstatus"  ==  "STOPPED" ]] && failed="true" && after_update_actions #run back after_update_actions function if the app was stopped prior to update
                    echo "$app_name,$new_full_ver" >> failed.txt
                    break
                else
                    echo_array+=("Error: Run Time($SECONDS) for $app_name has exceeded Timeout($timeout)")
                    echo_array+=("The application failed to be ACTIVE even after a rollback")
                    echo_array+=("Manual intervention is required\nAbandoning")
                    break
                fi
            else
                echo_array+=("Error: Run Time($SECONDS) for $app_name has exceeded Timeout($timeout)")
                echo_array+=("If this is a slow starting application, set a higher timeout with -t")
                echo_array+=("If this applicaion is always DEPLOYING, you can disable all probes under the Healthcheck Probes Liveness section in the edit configuration")
                break
            fi
        else
            [[ "$verbose" == "true" ]] && echo_array+=("Waiting $((timeout-SECONDS)) more seconds for $app_name to be ACTIVE")
            sleep 10
            continue
        fi
    done
fi


#Dump the echo_array, ensures all output is in a neat order. 
for i in "${echo_array[@]}"
do
    echo -e "$i"
done
}
export -f after_update_actions