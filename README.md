# Testing Config Connector in GKE

This provides a quick way to test the capabilities of Google's Config Connector

Run the normal Terraform commands and you should be good to go!
`terraform init`
`terraform plan`
`terraform apply`

Output value will be the administrative instance.  You should be able to ssh into this instance for all testing.  There will be example resources and applications in your home path.  For instance...

`kubectl apply -f ~/samples/resources/computenetwork/compute_v1beta1_computenetwork.yaml`

The above command will apply this spec.  This is a basic VPC.
```yaml
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeNetwork
metadata:
  labels:
    label-one: "value-one"
  name: computenetwork-sample
spec:
  routingMode: REGIONAL
  autoCreateSubnetworks: true
```
At this point, you should be able to see your resources with `kubectl` commands

```
kubectl get computenetwork
NAME                  AGE
computenetwork-sample 8s
```
You should also be able to see any provisioning errors and resource details
`kubectl describe computenetwork computenetwork-sample`
Any errors will be in the `Events` section
```
Type    Reason    Age                  From                       Message
----    ------    ----                 ----                       -------
Normal  Updating  4m35s                computenetwork-controller  Update in progress
Normal  UpToDate  3m38s (x2 over 14m)  computenetwork-controller  The resource is up to date
```
Requirements:
* Terraform version >= 0.12

|Variables|Description                  | Default Value
|------------------------------|-----------------------------|------------------------------|
|gcp_project|GCP  Project  to  deploy  too (Required)|No Default (Required)
|ssh_username|What  username  to  use  for  SSH  connections (Required)|No Default (Required)
|gcp_creds|Path  to  your  GCP  credential  file (Required)|~/.gcp/credentials.json
|prefix|Prefix assigned to all resources|gkedemo
|private_key|Private  key  to  use  for  SSH.  Public key must be in your project metadata (Required)|~/.ssh/id_rsa
|region|GCP  Region|us-central1
|zone|GCP Zone|us-central1-a
|machine_type|GCP  instance  type|n1-standard-1
|server_node_count|The number of Kubernetes nodes per region| 1