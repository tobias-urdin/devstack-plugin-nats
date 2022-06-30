#!/bin/bash

# Copyright 2022 Binero
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

# Save trace setting
XTRACE=$(set +o | grep xtrace)
set +o xtrace

function _download_nats {
    if [ ! -f ${FILES}/nats_${NATS_VERSION}.tar.gz ]; then
        wget ${NATS_URL} -O ${FILES}/${NATS_FILE}.tar.gz
    fi
}

function _install_nats {
    if [ ! -d ${FILES}/${NATS_FILE} ]; then
        tar -xvzf ${FILES}/${NATS_FILE}.tar.gz -C ${FILES}
    fi

    if [ ! -d ${NATS_DEST}/nats ]; then
        mkdir -p ${NATS_DEST}
        mv ${FILES}/${NATS_FILE} ${NATS_DEST}/nats
    fi

    if [ ! -f /etc/systemd/system/nats.service ]; then
    cat <<EOF | sudo tee /etc/systemd/system/nats.service >/dev/null
[Unit]
Description=NATS messaging server

[Service]
ExecStart=${NATS_DEST}/nats/nats-server -DV -l /opt/stack/logs/nats-server.log
User=$(whoami)
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload
    fi
}

function _install_nats_py {
    pip_install "-e git+https://github.com/tobias-urdin/nats.py.git@sync-client#egg=nats-py"
}

function _install_nats_backend {
    echo_summary "Installing NATS service"
    _download_nats
    _install_nats
    _install_nats_py
}

function _start_nats_backend {
    echo_summary "Starting NATS service"
    sudo systemctl start nats.service
}

function _stop_nats_backend {
    echo_summary "Stopping NATS service"
    sudo systemctl stop nats.service
}

function _cleanup_nats_backend {
    echo_summary "Cleanup NATS service"
    rm ${FILES}/${NATS_FILE}.tar.gz
    rm -rf ${NATS_DEST}/nats
    sudo rm -f /etc/systemd/system/nats.service
    sudo systemctl daemon-reload
}

if is_service_enabled nats; then
    function nats_get_transport_url {
        #echo "$RPC_SERVICE://$RPC_HOST:${RPC_PORT}"
        echo "nats://$SERVICE_HOST:4222"
    }

    function nats_iniset_rpc_backend {
        local package=$1
        local file=$2
        local section=${3:-DEFAULT}

        iniset $file $section transport_url $(nats_get_transport_url)
    }

    function iniset_rpc_backend {
        nats_iniset_rpc_backend $@
    }
    export -f iniset_rpc_backend

    # TODO(tobias-urdin): This is just to not fail when doing both, so
    # it's a copy paste from devstack lib, fix this with a setting.
    function rpc_backend_add_vhost {
        local vhost="$1"
        if is_service_enabled rabbit; then
            if [ -z `sudo rabbitmqctl list_vhosts | grep $vhost` ]; then
                sudo rabbitmqctl add_vhost $vhost
                sudo rabbitmqctl set_permissions -p $vhost $RABBIT_USERID ".*" ".*" ".*"
            fi
        fi
    }
    export -f rpc_backend_add_vhost

    if [[ "$1" == "source" ]]; then
        :
    elif [[ "$1" == "stack" && "$2" == "pre-install" ]]; then
        :
    elif [[ "$1" == "stack" && "$2" == "install" ]]; then
        _install_nats_backend
    elif [[ "$1" == "stack" && "$2" == "post-config" ]]; then
        _start_nats_backend
    elif [[ "$1" == "unstack" ]]; then
        _stop_nats_backend
    elif [[ "$1" == "clean" ]]; then
        _cleanup_nats_backend
    fi
fi

# Restore xtrace
$XTRACE
