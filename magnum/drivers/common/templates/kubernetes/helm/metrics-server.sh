#!/bin/bash

. /etc/sysconfig/heat-params

set -ex

step="metrics-server"
printf "Starting to run ${step}\n"

### Configuration
###############################################################################
CHART_NAME="metrics-server"

if [ "$(echo ${METRICS_SERVER_ENABLED} | tr '[:upper:]' '[:lower:]')" = "true" ]; then

    HELM_MODULE_CONFIG_FILE="/srv/magnum/kubernetes/helm/${CHART_NAME}.yaml"
    [ -f ${HELM_MODULE_CONFIG_FILE} ] || {
        echo "Writing File: ${HELM_MODULE_CONFIG_FILE}"
        mkdir -p $(dirname ${HELM_MODULE_CONFIG_FILE})
        cat << EOF > ${HELM_MODULE_CONFIG_FILE}
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: ${CHART_NAME}-config
  namespace: magnum-tiller
  labels:
    app: helm
data:
  install-${CHART_NAME}.sh: |
    #!/bin/bash
    set -e
    set -x
    mkdir -p \${HELM_HOME}
    cp /etc/helm/* \${HELM_HOME}

    if [ ! -z "${HTTP_PROXY}" ]; then
        export HTTP_PROXY=${HTTP_PROXY}
    fi
    if [ ! -z "${HTTPS_PROXY}" ]; then
        export HTTPS_PROXY=${HTTPS_PROXY}
    fi
    if [ ! -z "${NO_PROXY}" ]; then
        export NO_PROXY=${NO_PROXY}
    fi

    # HACK - Force wait because of bug https://github.com/helm/helm/issues/5170
    until helm init --client-only --wait
    do
        sleep 5s
    done
    helm repo update

    if [[ \$(helm history metrics-server | grep metrics-server) ]]; then
        echo "${CHART_NAME} already installed on server. Continue..."
        exit 0
    else
        helm install stable/${CHART_NAME} --namespace kube-system --name ${CHART_NAME} --version ${METRICS_SERVER_CHART_TAG} --values /opt/magnum/install-${CHART_NAME}-values.yaml
    fi

  install-${CHART_NAME}-values.yaml:  |
    image:
      repository: ${CONTAINER_INFRA_PREFIX:-gcr.io/google_containers/}metrics-server-${ARCH}
    args:
      - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
---

apiVersion: batch/v1
kind: Job
metadata:
  name: install-${CHART_NAME}-job
  namespace: magnum-tiller
spec:
  backoffLimit: 10
  template:
    spec:
      serviceAccountName: tiller
      containers:
      - name: config-helm
        image: ${CONTAINER_INFRA_PREFIX:-docker.io/openstackmagnum/}helm-client:dev
        command:
        - bash
        args:
        - /opt/magnum/install-${CHART_NAME}.sh
        env:
        - name: HELM_HOME
          value: /helm_home
        - name: TILLER_NAMESPACE
          value: magnum-tiller
        - name: HELM_TLS_ENABLE
          value: "true"
        volumeMounts:
        - name: install-${CHART_NAME}-config
          mountPath: /opt/magnum/
        - mountPath: /etc/helm
          name: helm-client-certs
      restartPolicy: Never
      volumes:
      - name: install-${CHART_NAME}-config
        configMap:
          name: ${CHART_NAME}-config
      - name: helm-client-certs
        secret:
          secretName: helm-client-secret
EOF
    }

fi

printf "Finished running ${step}\n"
