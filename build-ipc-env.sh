#!/bin/bash

MODE="$1"

if [[ "$MODE" != "qm-to-qm" && "$MODE" != "asil-to-qm" ]]; then
  echo "Usage: $0 [qm-to-qm|asil-to-qm]"
  exit 1
fi

echo "Creating IPC files for mode: $MODE"

# Define file paths for both modes
QMQM_SOCKET="/etc/qm/systemd/system/ipc_server.socket"
QMQM_SERVER="/etc/qm/containers/systemd/ipc_server.container"
QMQM_CLIENT="/etc/qm/containers/systemd/ipc_client.container"
QMQM_EXTRA_VOLUME=""

ASIL_SOCKET="/etc/systemd/system/ipc_server.socket"
ASIL_SERVER="/etc/containers/systemd/ipc_server.container"
ASIL_CLIENT="/etc/qm/containers/systemd/ipc_client.container"
ASIL_EXTRA_VOLUME="/etc/containers/systemd/qm.container.d/10-extra-volume.conf"

# Define file content based on mode
if [[ "$MODE" == "qm-to-qm" ]]; then
  echo "Cleaning up asil-to-qm files..."
  rm -f "$ASIL_SOCKET" "$ASIL_SERVER" "$ASIL_CLIENT" "$ASIL_EXTRA_VOLUME"

  LISTEN_PATH="%t/ipc.socket"
  VOLUME_PATH="/run/:/run/"

  SOCKET=$QMQM_SOCKET  
  SERVER=$QMQM_SERVER
  CLIENT=$QMQM_CLIENT
  EXTRA_VOLUME=""

  # Remove asil-to-qm versions
else
  echo "Cleaning up qm-to-qm files..."
  rm -f $QMQM_SOCKET $QMQM_SERVER $QMQM_CLIENT $QMQM_EXTRA_VOLUME

  SOCKET=$ASIL_SOCKET
  SERVER=$ASIL_SERVER
  CLIENT=$ASIL_CLIENT
  EXTRA_VOLUME="$ASIL_EXTRA_VOLUME"

  #LISTEN_PATH="%t/ipc/ipc_server.socket"
  #VOLUME_PATH="/run/ipc:/run/ipc"
  LISTEN_PATH="%t/ipc.socket"
  VOLUME_PATH="/run/:/run/"

fi

# Create ipc_server.socket
echo "Creating $SOCKET"
cat <<EOF > "$SOCKET"
[Unit]
Description=IPC Server Socket for $MODE
[Socket]
ListenStream=$LISTEN_PATH
SELinuxContextFromNet=yes

[Install]
WantedBy=sockets.target
EOF

if [[ -n "$EXTRA_VOLUME" ]]; then
echo "Creating $EXTRA_VOLUME"
cat <<EOF > "$EXTRA_VOLUME"
[Unit]
Requires=ipc_server

[Container]
Volume=/run/ipc:/run/ipc
EOF
fi

echo "Creating $SERVER"
# Create ipc_server.container
cat <<EOF > "$SERVER"
[Unit]
Description=Demo server service container ($MODE)
Requires=ipc_server.socket
After=ipc_server.socket
[Container]
Image=quay.io/yarboa/ipc-demo/ipc_server
Network=none
Environment=SOCKET_PATH=/run/ipc.socket
Volume=$VOLUME_PATH
SecurityLabelLevel=s0:c1,c2
[Service]
Restart=always
Type=notify
[Install]
WantedBy=multi-user.target
EOF

echo "Creating $CLIENT"
# Create ipc_client.container
cat <<EOF > "$CLIENT"
[Unit]
Description=Demo client service container ($MODE)
#Requires=ipc_server.socket
#After=ipc_server.socket
[Container]
Image=quay.io/yarboa/ipc-demo/ipc_client:latest
Network=none
Environment=SOCKET_PATH=/run/ipc.socket
Volume=$VOLUME_PATH
SecurityLabelLevel=s0:c1,c2
[Service]
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# Only restart services for qm-to-qm
if [[ "$MODE" == "qm-to-qm" ]]; then
  echo "Reloading systemd and restarting containers (qm-to-qm)..."
  systemctl daemon-reload
  systemctl restart qm
  sleep 15

  # make sure asil-to-qm env do not exist
  podman stop systemd-ipc_server &> /dev/null

  echo "qm: systemctl daemon-reload"
  podman exec -it qm bash -c "systemctl daemon-reload"

  echo "qm: systemctl restart ipc_server.socket"
  podman exec -it qm bash -c "systemctl restart ipc_server.socket"

  echo "qm: systemct status ipc_server.socket"
  podman exec -it qm bash -c "systemctl status ipc_server.socket"

  echo "qm: podman restart systemd-ipc_client"
  podman exec -it qm bash -c "podman restart systemd-ipc_client"
  sleep 15

  echo "qm: podman ps"
  podman exec -it qm bash -c "podman ps"

  echo "qm: podman logs systemd-ipc_client"
  podman exec -it qm bash -c "podman logs systemd-ipc_client"

else
  echo "systemctl daemon reload..."
  systemctl daemon-reload
  echo "restart ipc_server.socket"
  systemctl restart ipc_server.socket
  echo "restart ipc_server"
  systemctl restart ipc_server

  echo "restarting qm..."
  systemctl restart qm
  sleep 5

  echo "systemctl daemon-reload inside qm..."
  podman exec -it qm bash -c "systemctl daemon-reload"

  echo "systemctl status ipc_client"
  podman exec -it qm bash -c "systemctl status ipc_client"

  #echo "start ipc_client inside qm..."
  #podman exec -it qm bash -c "podman restart systemd-ipc_client"
  #sleep 15

  echo "podman ps inside qm..."
  podman exec -it qm bash -c "podman ps"
fi
