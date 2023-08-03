![shellcheck workflow](https://github.com/zzantozz/bash-mutex-server/actions/workflows/shellcheck.yml/badge.svg)

# Bash Mutex Server

If you're looking at this, you're probably asking "WHY???". Well, a need arose to coordinate some work across multiple
machines, and I didn't want to take the time to set up zookeeper, etcd, or anything like that. I wanted a very simple,
non-intrusive locking system that would ensure only one server could do some action at a time.

That's what this does: it's a TCP server that acts as a simple mutex, ensuring only one client can obtain the lock at a
time. It's also a corresponding client that works with the server and will fire off whatever work you give it when it
has the lock. It's all written in bash, so there are no real dependencies other than running it somewhere that has bash
and a few, common Linux tools.

## Caveat

There is one, small caveat, though. Since different versions of netcat have drastically different options for some
things, the way it's used here might not work everywhere. You might need to tweak the options so that the connection
gets closed in your netcat implementation. If the client connects to the server and hangs indefinitely, that's probably
what's going on.

## How?

Briefly, the server runs and listens on a TCP port for a "lock" message. When it receives one, it grants the lock to the
caller and closes that port. Then it listens on a different TCP port for an "unlock" message. When it receives one, it
closes the second port and opens the first one again. Rinse and repeat. Which port is open indicates the state of the
server.

Is it fragile? Sure. Is it stateful? Not at all, beyond remembering if the lock is available or not. Is it fair? Not
even close.

Does it work? Yes!

## Example

The server and client are written to work together out of the box with no configuration needed. You can run them on the
same machine in a couple of terminals. Just:

```bash
bash server.sh
```

and

```bash
bash client.sh
```

In the server terminal, you'll see that the client requested the lock and then released it.

In the client terminal, you'll see nothing. That's because the client's default action is to do nothing.

To make it a little more interesting, try running the client again with

```bash
HANDLER="echo 'hello world'" bash client.sh
```

You'll see the same thing as before, except the client terminal will write out "hello world".

## Configuring the server

You can configure how the server works with environment variables.

- `SERVER_ADDR`: the address that the server binds to. Default: `localhost`

- `LOCK_PORT`: the port that the server listens to for lock messages. Default: 5001

- `UNLOCK_PORT`: the port that the server listens to for unlock messages. Default: 5002

- `UNLOCK_PORT_TIMEOUT`: the timeout, in seconds, for the unlock port, in case a client dies without releasing the lock.
  Default: 30

## Configuring the client

As with the server, the client is configurable via environment variables. First, a set of variable determines where to
find the server. By design, they're identical to the server variables:

- `SERVER_ADDR`: the address of the server. Default: `localhost`

- `LOCK_PORT`: the port to send lock messages to on the server. Default: 5001

- `UNLOCK_PORT`: the port to send unlock messages to on the server. Default: 5002

In addition, you can configure how the client identifies itself to the server (for informational purposes only) and how
long it waits between attempts to obtain the lock:

- `MY_ID`: the client's id, which is logged by the server. Default: `$(hostname -f)`

- `SLEEP_TIME_AFTER_NO_LOCK`: time, in seconds, to sleep after failing to obtain the lock. The client is basically an
  infinite loop until it gets the lock. This is how long to sleep before trying again. Default: 10

Finally, you have to configure the client with the work you want it to do *and* how to know when the work is finished.
For my use case, I couldn't just run a simple command and wait for it to finish. The "finished" condition is separate
from the command to run.

- `ACTION`: the action to take when the client gets the lock. This is any valid command. The client
  runs `eval "$action"` to start it. Default: `true`

- `FINISHED_TEST`: a command to test if the action has finished so the client can release the lock. This is also any
  valid command, which is run as `eval "$finished_test"`. The action is considered finished when this command exits with
  status code 0. Default: `true`

- `SLEEP_BETWEEN_FINISH_TESTS`: time, in seconds, to wait between finish tests. The first test runs immediately after
  the action completes. Then the client waits in a loop for the "finished test" to exit with status code 0. This is how
  long it waits between tests. Default: 10

## FAQs

### How do I make the client do something repeatedly?

That's up to you. The client's job is to compete for the lock, run an action, release the lock, and exit. If you want to
repeat an action, write a loop that includes a call to the client.

### How can I be sure this thing works?

There's a `lock-reporter.sh` script here that can be used as the client action. It mimics doing some work by sleeping
for a random time and writes out a line of output indicating when the "work" started and ended. You can use this as the
client's action and run it in multiple places at once. If you capture the output of the script in a file, you can
aggregate all the lock times and verify that none of them overlap, which is, after all, the entire point of this
exercise: to be sure that a piece of work is done exactly one time concurrently anwhere.

For example, start a server, and run this 5, 10, or 100 different times (configured to reach the server if it's not
local):

```bash
rm -f locks.log; for i in {1..4}; do rm -f finished && ACTION="bash lock-reporter.sh >> locks.log; touch finished" FINISHED_TEST="[ -e finished ]" bash client.sh; sleep 60; done
```

Then gather up all the `locks.log` files. If you put them all under a directory named `locks`, then this beefy one-liner
I came up with will verify that none of the ranges overlap.

```bash
unset prev_start prev_end failed; while read -r -a range; do start="${range[0]}"; end="${range[1]}"; echo -n "$start - $end "; if [ -z "$prev_start" ]; then echo "First line!"; prev_start="$start"; prev_end="$end"; else echo -n "is $prev_end < $start? "; if [ "$prev_end" -lt "$start" ]; then echo yep; else echo nope; failed=true; fi; fi; prev_start="$start"; prev_end="$end"; done < <(cat locks/* | sort -k 6 | awk '{print $6 " " $8}'); [ -z "$failed" ] || echo "There was an overlap!"
```

### The client connected to the server, but then it hangs forever.

1. That's not a question.

2. It's probably because your netcat implementation differs from the one where I wrote this. Different netcats have
   different ways of saying "close the connection after sending/receiving some data. Figure out what's right for your
   system and change the netcat options appropriately. A google search for "make netcat close the connection" should be
   illuminating.
