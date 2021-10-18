# Connecting private clusters to argocd

This repository is offering a solution for those that want to add remote kubernetes clusters that are behind network security mechanisms (such as a bastion) to argocd. There are solutions to this issue, for example [Inlets tunnels](https://inlets.dev/), but these are paid ones. We offer a free, open source and easy solution which is entirely under your control.

### The issue:
To add a cluster to argocd, you will need:
* The kubeconfig of the cluster you want to add
* Cluster must be accessible to the argocd server pod, network wise.

The problem is the kubernetes server address might not be directly accessible over internet, especially when using a kube from a cloud provider. For example at our company, we have multiple clusters that can be accessible only from a bastion instance (a virtual machine which runs kubectl and has actually access to the kubernetes API). 
The way we did deployments was to connect to the bastion and use that machine to deploy to the cluster. But that quickly became annoying, esepcially when we wanted to adopt Argocd in our toolkit.


### The solution

To have multiple clusters accessible in argocd, we had to create ssh tunnels to those clusters through the bastion instances. We achieved this by using an autossh image, add it inside the argocd server & application controller pods and open tunnels on local ports. Since opening a tunnel inside a container inside a pod opens that port for all the containers in that pod, that meant the argocd could access the tunnelled resource.

### The basics of SSH tunneling

You can also read more on interente, but below is the basic gist of it:
```
ssh user@remote.host.domain -N -f -L 4040:target.host.domain:5050
```
Will create an ssh tunnel to port 5050 on the remote `system target.host.domain` which is accesible on your local machine at `localhost:4040` using 
`user@remote.host.domain` as the remote middleman between your machine and final target.

Now meet [autossh](https://linux.die.net/man/1/autossh#:~:text=autossh%20is%20a%20program%20to,rstunnel%20(Reliable%20SSH%20Tunnel).). Autossh is a reliable ssh tool that monitors and keeps a ssh connection up. It is very similar to good old ssh except more reliable.


## Installation

This guide assumes you already have argocd deployed on your cluster as specified in the [argocd docs](https://argo-cd.readthedocs.io/en/stable/getting_started/).

First build yourself a `multi-ssh` image using the provided [Dockerfile](https://github.com/pdstefan/argocd-for-private-clouds/blob/main/Dockerfile). 

Next, create a configmap from the file containing the ports and addresses needed to open tunnels. 

An example of such file is below, change it to your needs:
```
# LOCAL PORT | TARGET HOST | TARGET PORT | REMOTE HOST | REMOTE PORT | SSH_KEY_PATH
# ---------------------------------------------------------------------------------
6443 10.21.4.64 5443 user@80.158.6.76 22 /etc/cluster_keys/ssh-privatekey_1     
7443 10.21.5.232 5443 user@80.158.6.208 22 /etc/cluster_keys/ssh-privatekey_2 
8443 192.168.0.83 5443 user@80.158.6.215 22 /etc/cluster_keys/ssh-privatekey_3
#----------------------------------------------------------------------------------
```

***EXPLANATIONS:***
```
LOCAL PORT = port that will be open on local machine.
TARGET HOST = ip address of final machine, that would be the kubernetes server address we try to tunnel.
TARGET PORT = kubernetes server port, usually 5443
REMOTE HOST = the user@address of the machine that has access to kubernetes server, the middleman.
REMOTE PORT = the port of the remote host that is used for ssh connections.
SSH_KEY_PATH = the path to the ssh key for a specific tunnel inside the container. (must be where you mounted your key)
```

Generate the configmap from the file you just created and apply it to the argocd namespace:
```
 kubectl -n argocd create configmap cluster-tunnels --from-file=<path/to/targets_file>
```
Next create secret for your ssh key(s), edit command and add more `--from-file` parameters if you need more than one key:

```
kubectl -n argocd create secret generic multi-autossh-keys  --from-file=ssh-privatekey=</path/to/ssh/ssh-privatekey_1> 
```

Edit the file [multi-autossh-patch.yaml](https://github.com/pdstefan/argocd-for-private-clouds/blob/main/multi-autossh-patch.yaml) according to your set up. Specifiy your image name you just built and check if everything is in order. Check if your ssh path in configmap matches the mount path of the ssh keys secret. Also check that the env `TUNNEL_PARAMETERS_CM` matches the mount path of cm file.


Next, patch the deployment for the argocd-server with the data:

```
kubectl -n argocd patch deployment argocd-server --patch "$(cat multi-autossh-patch.yaml)"
```

Then patch statefulset for arocd-application-controller:
```
kubectl -n argocd patch sts argocd-application-controller --patch "$(cat multi-autossh-patch.yaml)"
```

Argocd-server and arocd-application-controller both check on the cluster server address, that s why we need both of them to have access to tunnelled clusters.

Once you successfully patched and the containers are up and running it should look like below:
```
NAME                                  READY   STATUS    RESTARTS   AGE
argocd-application-controller-0       2/2     Running   0          2d17h
argocd-dex-server-6668dbb864-kcpl2    1/1     Running   0          3d17h
argocd-redis-65489fc4cd-kqr5w         1/1     Running   0          12d
argocd-repo-server-56cb46d7cc-26zst   1/1     Running   0          3d17h
argocd-server-6d69ff9f6f-84l4v        2/2     Running   0          2d17h
```

Try running an exec command (example below) in the multi-autossh container for argocd-server and see if the tunnels are open:

```
kubectl -n argocd exec -it argocd-server-6d69ff9f6f-84l4v -c multi-autossh -- /bin/bash -c "netstat -tlpn"
```
Notice the tunnels running on port 6443,7443, 8443:
```
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name    
tcp        0      0 127.0.0.1:7443          0.0.0.0:*               LISTEN      60/ssh              
tcp        0      0 127.0.0.1:8443          0.0.0.0:*               LISTEN      85/ssh              
tcp        0      0 127.0.0.1:6443          0.0.0.0:*               LISTEN      35/ssh              
tcp6       0      0 :::8080                 :::*                    LISTEN      -                   
tcp6       0      0 :::8083                 :::*                    LISTEN      -          
```

Do the same for argocd-application-controller, which should bring similar results.

Finally you can proceed to add a new cluster as specified in [argocd documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/commands/argocd_cluster_add/)

Login in with argocd-cli:

```argocd login <argocd-domain>```
```argocd cluster add --kubeconfig [path_to_kubeconfig] ```

A list of contexts from that file will be shown for you to choose:
Run the command again with the context name:

```argocd cluster add [context_name] --kubeconfig [path_to_kubeconfig]```

**EXTREMLY IMPORTANT** **Do not forget to change the server address in kubeconfig before adding cluster !!!**

Before:

``
"cluster":{"server":"https://192.168.0.83:5443""
``

After:

``
"cluster":{"server":"https://kubernetes:8443"
``

The cluster is now accessible at kubernetes:8443 inside argocd container (kubernetes is an alias we set up for localhost in hosts file, to solve tls issues with the kubernetes server).

Once a cluster added, you should see it added successfully in the argocd UI.  See below an example of multiple clusters added, both remote accessible, and remote tunnelled:

![argocd multiple-external-clusters](https://imgur.com/m5PqTkl.png)

**Thank you very much.
If you want to improve this solution, you are free to contribute.**
