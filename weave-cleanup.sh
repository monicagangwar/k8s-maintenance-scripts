#!/bin/bash

# Generally as nodes come up and go down, weave allocates/deallocates pod cidrs to them.
# Due to some race condition sometimes weave db gets corrupted with incosistent
# ip addresses allocated to some nodes.
# This causes pods to go into ContainerCreating phase as k8s is unable to allocate ip
# address to them hence weave needs to be manually corrected.
# For this weave db needs to be manually removed, restarting the pod does not work as
# weave pods mount /var/lib/weave/weave-netdata.db on host and data is persisted.
# This script removes the weave db and restarts weave pod causing db to be created again
# with data taken up from annotation in weave configmap persisted in k8s itself.

echo Starting NODES cleanup ...
kubectl get nodes -o json | jq -cr .items[].metadata.name | while read node
do
      echo "Removing weave db from node -> $node"
      node_ip=`kubectl get node $node -o json | jq -cr '.status.addresses[] | select(.type == "InternalIP") | .address'`
      ssh -i ~/.ssh/dev-ap-southeast-1 -tt -o ConnectTimeout=10 -o StrictHostKeyChecking=no admin@$node_ip "sudo rm /var/lib/weave/weave-netdata.db"
      pod=`kubectl get pods -o wide -n=kube-system | grep $node | grep weave | awk '{print $1}'`
      echo "Restarting weave pod -> $pod in node -> $node"
      kubectl delete pod -n kube-system $pod
      echo "Waiting for new pod to come up ..."
      count=0
      while true
      do
        if [[ $count == 5 ]]; then
          echo "Waited for 25 seconds for new pod to come up in node -> $node, moving on ..."
          break
        fi
        pod_present=`kubectl get pods -o wide -n=kube-system | grep $node | grep weave | grep -v Terminating | wc -l`
        echo "pod found for weave in node -> $node : $pod_present"
        if [[ $pod_present == 0 ]]; then
          continue
        else
          break
        fi
        count=$((count + 1))
        echo "sleeping for 5 seconds ..."
        sleep 5
      done
done
