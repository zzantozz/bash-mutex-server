#!/bin/bash

start="$(date +%s)"
lock_hold_time="$((RANDOM % 30 + 15))"
sleep "$lock_hold_time"
end="$(date +%s)"
echo "Held lock for $lock_hold_time from $start to $end"
