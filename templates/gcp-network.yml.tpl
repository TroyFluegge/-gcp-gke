apiVersion: app.terraform.io/v1alpha1
kind: Workspace
metadata:
 name: gcp-network
spec:
 organization: ${tfc_org}
 secretsMountPath: "/tmp/secrets"
 module:
   source: "terraform-google-modules/network/google"
   version: "2.3.0"
 outputs:
   - key: url
     moduleOutputName: network_self_link
 variables:
   - key: network_name
     value: "tfc-operator-test"
     sensitive: false
     environmentVariable: false
   - key: project_id
     value: "${gcp_project}"
     sensitive: false
     environmentVariable: false
   - key: subnets
     value: '[{subnet_name = "subnet-01", subnet_ip = "10.10.10.0/24", subnet_region = "us-west1"}]' 
     sensitive: false
     hcl: true
     environmentVariable: false
   - key: GOOGLE_CREDENTIALS
     sensitive: true
     environmentVariable: true
   - key: CONFIRM_DESTROY
     value: "1"
     sensitive: false
     environmentVariable: true
