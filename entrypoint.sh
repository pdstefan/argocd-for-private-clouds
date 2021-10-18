#!/usr/bin/dumb-init /bin/bash
input=$TUNNEL_PARAMETERS_CM
echo "[INFO] Started tunnels."
echo "[INFO] Using parameters found at path $input."
eval $(ssh-agent -s)
while read line
do
  if [[ $line == '#'* ]]; then
    continue
  fi
  LOCAL_PORT=$(echo $line | awk '{ print $1}')
  TARGET_HOST=$(echo $line | awk '{ print $2}')
  TARGET_PORT=$(echo $line | awk '{ print $3}')
  REMOTE_HOST=$(echo $line | awk '{ print $4}')
  REMOTE_PORT=$(echo $line | awk '{ print $5}')
  SSH_KEY_PATH=$(echo $line | awk '{ print $6}')
  echo "[INFO] Starting autossh tunnel: $LOCAL_PORT $TARGET_HOST $TARGET_PORT $REMOTE_HOST $REMOTE_PORT using ssh key from path $SSH_KEY_PATH."
  cat "$SSH_KEY_PATH" | ssh-add -k -
  autossh \
  -M 0 \
  -N \
  -t -t -f \
  -o StrictHostKeyChecking=no \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  -L $LOCAL_PORT:$TARGET_HOST:$TARGET_PORT $REMOTE_HOST \
  -p $REMOTE_PORT
done < "$input"

# Using this to never exit the entrypoint script since we started multiple autossh connections in the background
tail -f /dev/null
