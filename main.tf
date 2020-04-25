provider "google" {
  # credentials = file("${var.gcp_creds}") # Left in for local terraform CLI
  project     = var.gcp_project
  region      = var.region
  zone        = var.zone
}

#-------------------------------------------------------------------------------------------------------#
# Make sure the K8s and Compute services are enabled
# There may be access errors if the serviceAccounts for these services are missing or misconfigured
# Disabling and re-enabling the services will create these accounts and may fix any permissions problems
resource "google_project_service" "enable_kubernetes_api" {
  project            = var.gcp_project
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "enable_compute_api" {
  project            = var.gcp_project
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}
#-------------------------------------------------------------------------------------------------------#

# This is the service account used both for the administrative client instance in the K8s cnrm namespace
resource "google_service_account" "cnrm-system" {
  account_id   = "cnrm-system"
  display_name = "Config Connector Service Account"
}

# Service account for K8s
resource "google_service_account" "k8s-svc" {
  account_id   = "k8s-svc"
  display_name = "Kubernetes Service Account"
}

# Yes, owner is needed.  I didn't like it either but errors will occur with you `kubectl apply -f install-bundle-gcp-identity/`
# It would take further research to determine a better, least privileged, approach
resource "google_project_iam_member" "cnrm-system-role" {
  project = var.gcp_project
  role    = "roles/owner"
  member  = "serviceAccount:${google_service_account.cnrm-system.email}"
}

resource "google_project_iam_member" "k8s-svc-role" {
  project = var.gcp_project
  role    = "roles/container.admin"
  member  = "serviceAccount:${google_service_account.k8s-svc.email}"
}

data "template_file" "example" {
  template = "${file("${path.module}/templates/gcp-network.yml.tpl")}"
  vars = {
    gcp_project = "${var.gcp_project}"
    tfc_org     = "${var.tfc_org}"
  }
}

data "template_file" "terraformrc" {
  template = "${file("${path.module}/templates/credentials.tpl")}"
  vars = {
    tfc_usertoken = "${var.tfc_usertoken}"
  }
}

# Create administrative instance that will setup Config Connector
# The connection information is outputed
resource "google_compute_instance" "client_instance" {
  name         = "${var.prefix}-client"
  machine_type = var.machine_type
  depends_on   = [google_project_service.enable_compute_api]
  service_account {
    email  = google_service_account.cnrm-system.email # Using the same service account that Config Connector is using
    scopes = ["cloud-platform"]
  }
  boot_disk {
    initialize_params {
      image = "centos-cloud/centos-7"
    }
  }
  network_interface {
    network = "default"
    access_config {
    }
  }
  provisioner "remote-exec" {
    connection {
      user        = var.ssh_username
      host        = self.network_interface[0].access_config[0].nat_ip
      #private_key = file(var.private_key)  # Left in for local terraform CLI
      private_key = var.private_key
    }
    inline = [
      "sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo",                              # Added due to some of the examples using docker
      "sudo yum install -y kubectl git yum-utils device-mapper-persistent-data lvm2 docker-ce docker-ce-cli containerd.io",      # Installing tools
      "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region}",               # Fetch credentials from the K8s cluster for the client
      "gcloud iam service-accounts keys create --iam-account ${google_service_account.cnrm-system.email} key.json",              # Create service account key
      "kubectl create namespace ${google_service_account.cnrm-system.account_id}",                                               # Create the K8s namespace to config connector / infrastructure resources
      "kubectl create secret generic gcp-key --from-file key.json --namespace ${google_service_account.cnrm-system.account_id}", # K8s secret with previously created service account key
      "gsutil cp gs://cnrm/latest/release-bundle.tar.gz release-bundle.tar.gz",                                                          # Download config connector install
      "tar zxvf release-bundle.tar.gz",                                                                                                  # Extract tar file
      "kubectl apply -f install-bundle-gcp-identity/",                                                                                   # Apply the config connector manifests
      "kubectl config set-context --current --namespace ${google_service_account.cnrm-system.account_id}",                               # Defaulting namespace to cnrm-system
      "kubectl annotate namespace ${google_service_account.cnrm-system.account_id} cnrm.cloud.google.com/project-id=${var.gcp_project}", # Needed to default the project ID.. errors occur without this
      "curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash",                                               # helm install...bash from curl yolo
      "curl -s https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh  | bash",                    # kustomize install...yolo again
      "sudo mv kustomize /usr/local/bin",
      "kubectl create ns tfc-operator",
      "sudo mkdir /etc/terraform",
      "sudo cat > ~/credentials <<EOL\n${data.template_file.terraformrc.rendered}\nEOL",
      "sudo mv credentials /etc/terraform/credentials",
      "kubectl create -n tfc-operator secret generic terraformrc --from-file=/etc/terraform/credentials",
      "tr '\n' ' ' < key.json >> new.json",
      "kubectl create -n tfc-operator secret generic workspacesecrets --from-file=GOOGLE_CREDENTIALS=new.json",
      "sudo cat > ~/gcp_network.yml <<EOL\n${data.template_file.example.rendered}\nEOL",
      "sudo git clone https://github.com/hashicorp/terraform-helm",
      "helm install -n tfc-operator operator ./terraform-helm --set=\"global.enabled=true\"",
      "rm -Rf *.json" # Clean up the key on disk
    ]
  }
}

# Nothing too crazy here.. Needed a depends_on due to how long it takes to enable the service
resource "google_container_cluster" "primary" {
  name                     = "${var.prefix}-cluster"
  location                 = var.region
  depends_on               = [google_project_service.enable_kubernetes_api]
  remove_default_node_pool = true
  initial_node_count       = 1

  node_config {
    service_account = google_service_account.k8s-svc.email
  }

  master_auth {
    username = ""
    password = ""

    client_certificate_config {
      issue_client_certificate = false
    }
  }
}

resource "google_container_node_pool" "primary_preemptible_nodes" {
  name       = "node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = var.server_node_count

  node_config {
    preemptible     = true
    machine_type    = var.machine_type
    service_account = google_service_account.k8s-svc.email

    metadata = {
      disable-legacy-endpoints = "true"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
  }
}