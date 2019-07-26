#!/bin/sh

. /etc/sysconfig/heat-params

mkdir -p /etc/kubernetes/
cp /etc/pki/tls/certs/ca-bundle.crt /etc/kubernetes/ca-bundle.crt

if [ -n "${TRUST_ID}" ]; then
    KUBE_OS_CLOUD_CONFIG=/etc/kubernetes/cloud-config

    # Generate a the configuration for Kubernetes services
    # to talk to OpenStack Neutron and Cinder
    CLOUD_CONFIG=$(cat <<EOF
[Global]
auth-url=$AUTH_URL
user-id=$TRUSTEE_USER_ID
password=$TRUSTEE_PASSWORD
trust-id=$TRUST_ID
ca-file=/etc/kubernetes/ca-bundle.crt
[LoadBalancer]
use-octavia=$OCTAVIA_ENABLED
subnet-id=$CLUSTER_SUBNET
floating-network-id=$EXTERNAL_NETWORK_ID
create-monitor=yes
monitor-delay=1m
monitor-timeout=30s
monitor-max-retries=3
[BlockStorage]
bs-version=v2
EOF
)
    echo $CLOUD_CONFIG > $KUBE_OS_CLOUD_CONFIG

    # Provide optional region parameter if it's set.
    if [ -n "${REGION_NAME}" ]; then
        sed -i '/ca-file/a region='${REGION_NAME}'' $KUBE_OS_CLOUD_CONFIG
    fi

    # backwards compatibility, some apps may expect this file from previous magnum versions.
    cp ${KUBE_OS_CLOUD_CONFIG} /etc/kubernetes/kube_openstack_config

    # Append additional networking config to config file provided to openstack
    # cloud controller manager (not supported by in-tree Cinder).
    cat > ${KUBE_OS_CLOUD_CONFIG}-occm <<EOF
$CLOUD_CONFIG
[Networking]
internal-network-name=$CLUSTER_NETWORK
EOF
fi
