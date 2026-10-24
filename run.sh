#!/usr/bin/env bash
#
# Keep Buyin up.
#
# On a LAN a dead process was a private annoyance. On a public domain it is a
# stranger seeing a 502 on someone else's hostname, so it needs to come back
# by itself.
#
# Three things beyond a plain restart loop, each earning its place:
#
#   Logs persist. Only ~/projects, ~/worktrees, ~/dotfiles, ~/.claude, ~/.ssh,
#   ~/.config/herdr and ~/letterbox survive a container recreate. A log in ~/
#   is destroyed by exactly the event you would most want to read it after.
#
#   One instance only. Two copies of this loop race for the port; the loser
#   crash-loops forever while the winner looks healthy, which is a genuinely
#   confusing way to spend an evening.
#
#   Backoff on fast failures. A process that dies instantly would otherwise be
#   restarted thirty times a minute, burning CPU and burying the real error in
#   its own restart notices.
#
# Start:  nohup ./run.sh >/dev/null 2>&1 &
# Stop:   kill the run.sh process (the child dies with it)
#
# Does NOT survive a container recreate. Re-run it after one.
set -uo pipefail

NAME="buyin"
cd "$(dirname "$0")" || exit 1

LOG_DIR="$HOME/projects/.logs"
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="."
LOG="$LOG_DIR/$NAME.log"
LOCK="$LOG_DIR/$NAME.lock"

# Refuse to be the second copy. Non-blocking: fail loudly rather than queue.
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "$NAME: another run.sh already holds the lock — not starting a second" >&2
  exit 1
fi

say() { echo "[$(date -Is)] $*" >> "$LOG"; }

# Keep the log from growing without bound; nobody watches a file that only
# gets bigger.
rotate() {
  local size
  size=$(stat -c%s "$LOG" 2>/dev/null || echo 0)
  if [ "$size" -gt 10485760 ]; then
    mv -f "$LOG" "$LOG.1"
    say "$NAME: rotated log at 10MB"
  fi
}

trap 'say "$NAME: run.sh stopping"; kill 0 2>/dev/null; exit 0' INT TERM

say "$NAME: run.sh started (pid $$)"
delay=2
while true; do
  rotate
  started=$SECONDS
  node server.mjs >> "$LOG" 2>&1
  code=$?
  ran=$(( SECONDS - started ))

  if [ "$ran" -lt 10 ]; then
    # Died almost immediately — a port clash or a syntax error, not a blip.
    delay=$(( delay * 2 )); [ "$delay" -gt 60 ] && delay=60
    say "$NAME: exited $code after ${ran}s (fast failure) — retrying in ${delay}s"
  else
    delay=2
    say "$NAME: exited $code after ${ran}s — restarting in ${delay}s"
  fi
  sleep "$delay"
done
