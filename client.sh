#!/bin/bash

###
# A client for the simple, no-dependencies tcp mutex server.
#
# This waits to obtain a lock from the companion lock server. When it obtains the lock, it forks a configurable action
# script to the background and then polls for completion by periodically calling a configurable "finished" script. When
# the finished script returns success (status code 0), it releases the lock and exits.
#
# In case it fails to obtain the lock, it sleeps for a while and tries again.
#
# The client has sane defaults so that if you run it and the companion server on the same machine, they'll work together
# and demonstrate how the system works. Use environment variables to override important settings, like where to reach
# the server, the scripts that do the actual work, and the various sleep times.

# Configure the lock server to talk to
server_addr=${SERVER_ADDR:-localhost}
lock_port=${LOCK_PORT:-5001}
unlock_port=${UNLOCK_PORT:-5002}

# Configure what we do when we get a lock
action=${ACTION:-true}
finished_test=${FINISHED_TEST:-true}
sleep_between_finish_tests=${SLEEP_BETWEEN_FINISH_TESTS:-10}

# Configure how I identify myself to the lock server
my_id=${MY_ID:-$(hostname -f)}

# Configure how long to wait after failing to obtain the lock before we try again
sleep_time_after_no_lock=${SLEEP_TIME_AFTER_NO_LOCK:-10}

# Keep trying for the lock until we get the work done.
work_done=false
until [ "$work_done" = true ]; do
  # Request the lock from the server.
  lock_msg="lock:$my_id:$(date +%s)"
  response=$(echo "$lock_msg" | nc -w2 "$server_addr" "$lock_port")
  # Only if the server specifically responded, proceed.
  if [ "$response" = oklocked ]; then
    # Run the work in the background, and poll for completion. This uses two different scripts. One will have to know
    # how the other works.
    eval "$action" &
    while ! eval "$finished_test"; do
      sleep "$sleep_between_finish_tests"
    done
    # Try to let the server know the lock is released, but don't wait forever.
    attempt=1
    unlocked=false
    until [ "$unlocked" = true ] || [ $attempt -gt 5 ]; do
      unlock_msg="unlock:$my_id:$(date +%s)"
      response=$(echo "$unlock_msg" | nc -w2 "$server_addr" "$unlock_port")
      if [ "$response" = okunlocked ]; then
        unlocked=true
      else
        sleep 1
        attempt=$((attempt+1))
      fi
    done
    work_done=true
  else
    # If we didn't obtain the lock, sleep for a while before trying again.
    sleep "$sleep_time_after_no_lock"
  fi
done
