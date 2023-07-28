#!/bin/bash

###
# A simple, no-dependencies mutex server that lets clients request a lock via tcp.
#
# When this runs, it listens on a port for tcp connections. The first(-ish) client that connects and sends a string like
# "lock:<client-id>:<timestamp>" will receive the message "oklocked", meaning that client can now proceed with the
# guarantee that no other clients have obtained the single lock.
#
# After the lock is handed out, the first port is closed, and a new port is opened, which waits for the lock to be
# released. When a client connects to this new port and sends a string like "unlock:<client-id>:<timestamp>", this
# second port is closed, and the first one is opened again, making the lock available to the next available client.
#
# In case a client dies without releasing the lock, there's a timeout on the unlock port. When the timeout expires, the
# lock will be released automatically.
#
# FAIRNESS WARNING! This server doesn't try to be fair at all. It's entirely possible for the same, one client to
# receive the lock repeatedly, regardless of how many are competing for the lock. Control this by having the client
# sleep for a reasonable amount of time after it gets a lock and does its work. It should sleep long enough for all
# other clients to reasonably perform their work.
#
# The server has sane defaults so that if you run it and the companion client on the same machine, they'll work together
# and demonstrate how the system works. Use environment variables to override important settings, like the ports used
# and the unlock timeout.

# Configure where the server listens
server_addr=${SERVER_ADDR:-localhost}
lock_port=${LOCK_PORT:-5001}
unlock_port=${UNLOCK_PORT:-5002}

# Configure done port timeout. If a client dies without releasing the lock, this is how long it'll be before we release
# it automatically.
unlock_port_timeout=${UNLOCK_PORT_TIMEOUT:-30}

# A server runs forever. Just kill it when you're done. Clients that can't connect shouldn't assume they have the lock.
while true; do
  echo "Listening for lock request"
  input=$(echo oklocked | nc -w 1 -l "$server_addr" "$lock_port")
  # Only proceed if it looks like a lock request. We don't want to be triggered by a random port scan.
  IFS=':' read -r -a fields <<<"$input"
  if [ "${fields[0]}" != "lock" ]; then
    echo "Not a lock message: $input"
    continue
  fi
  echo "Lock requested by ${fields[1]} at ${fields[2]}"
  # Once the lock is handed out, wait for the unlock signal.
  while true; do
    input=$(echo okunlocked | timeout "$unlock_port_timeout" nc -w 1 -l "$server_addr" "$unlock_port")
    unlock_status="$?"
    # If the port timed out, go back to waiting for a lock request
    if [ "$unlock_status" -eq 124 ]; then
      echo "Timed out waiting for unlock"
      break
    fi
    # Again, only unlock if it's really an unlock request, not some random tcp connection.
    IFS=':' read -r -a fields <<<"$input"
    if [ "${fields[0]}" == "unlock" ]; then
      echo "Lock released by ${fields[1]} at ${fields[2]}"
      break
    else
      echo "Not an unlock message: $input"
      continue
    fi
  done
done
