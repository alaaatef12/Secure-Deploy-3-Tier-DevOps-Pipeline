#!/bin/bash

GROUP="deployG"
COUNT=0

echo "Users not in group $GROUP:"
echo "---------------------------------------------"
printf "%-15s %-10s %-25s %-20s\n" "Username" "UID" "Shell" "Last Login"
echo "---------------------------------------------"

while IFS=: read -r user _ uid _ _ _ home shell; do
    if [ "$uid" -ge 1000 ] && ! id -nG "$user" | grep -qw "$GROUP"; then
        last_login=$(lastlog -u "$user" | awk 'NR==2 {print $4, $5, $6, $7}')
        printf "%-15s %-10s %-25s %-20s\n" "$user" "$uid" "$shell" "$last_login"
        ((COUNT++))
    fi
done < /etc/passwd

echo "---------------------------------------------"
echo "Total users not in $GROUP: $COUNT"
