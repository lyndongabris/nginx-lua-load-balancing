#! /bin/bash

function log {
    message="$1"
    printf "\n+++ ${message}" 
}

# Create Kind Cluster
kind create cluster --name sandbox --config config.yaml

# containers=$(docker ps --format "{{.ID}}:{{.Image}}" | grep "kindest/node:" | cut -d ':' -f 1)
# updateCertsCommand="update-ca-certificates"

# # Loop through the list of containers, update certs and restart the container.
# # The restart is necessary for the node containers to pickup the mounted Zscaler Root CA certificate (see config.yaml).
# for container_id in $containers; do
#     # Run update CA certificate command
#     docker exec $container_id $updateCertsCommand
#     echo "Restarting container, please wait."
#     docker restart $container_id
#     echo "Restart complete."
# done

log "Waiting for node to be ready.."
kubectl --context kind-sandbox wait --for=condition=Ready node/sandbox-control-plane
log "Applying label to node.."
kubectl --context kind-sandbox label nodes sandbox-control-plane ingress-ready=true

kubectl --context kind-sandbox apply -f ./ingress-nginx.yaml

log "Waiting for ingress nginx to be ready.."
# kubectl --context kind-sandbox wait -n ingress-nginx --for=condition=Ready pod -l app.kubernetes.io/name="ingress-nginx"
kubectl --context kind-sandbox -n ingress-nginx rollout status deployment ingress-nginx-controller --timeout=300s

log "Deploying configmap with lua.."
kubectl --context kind-sandbox apply -f ./lua-configmap.yaml -n ingress-nginx
kubectl --context kind-sandbox apply -f ./pool-selection-configmap.yaml -n ingress-nginx

log "Patching nginx controller with updated config.."
kubectl --context kind-sandbox patch deployment ingress-nginx-controller -n ingress-nginx \
  --type='json' \
  -p='[
    {
      "op": "add",
      "path": "/spec/template/spec/volumes/-",
      "value": {
        "name": "lua-scripts",
        "configMap": {
          "name": "lua-scripts"
        }
      }
    },
    {
      "op": "add",
      "path": "/spec/template/spec/volumes/-",
      "value": {
        "name": "pool-config",
        "configMap": {
          "name": "pool-config"
        }
      }
    },
    {
      "op": "add",
      "path": "/spec/template/spec/containers/0/volumeMounts/-",
      "value": {
        "name": "lua-scripts",
        "mountPath": "/etc/nginx/custom-lua/pool-selection.lua",
        "subPath": "pool-selection.lua"
      }
    },
    {
      "op": "add",
      "path": "/spec/template/spec/containers/0/volumeMounts/-",
      "value": {
        "name": "pool-config",
        "mountPath": "/etc/nginx/custom-lua/pool-config.lua",
        "subPath": "pool-config.lua"
      }
    }
  ]'

log "Waiting for ingress nginx to be ready.."
# kubectl --context kind-sandbox wait -n ingress-nginx --for=condition=Ready pod -l app.kubernetes.io/name="ingress-nginx"
kubectl --context kind-sandbox -n ingress-nginx rollout status deployment ingress-nginx-controller --timeout=300s

log "Installing apps.."
kubectl --context kind-sandbox apply -f ./web-app-1.yaml
kubectl --context kind-sandbox apply -f ./web-app-2.yaml

log "Configuring ingress.."
kubectl --context kind-sandbox apply -f ./ingress.yaml
