locals {
  module_path = replace(path.module, "\\", "/")
}

provider "google" { 
  credentials = file(var.credentials_file)
  project     = var.project
  region      = var.region
}

provider "helm" {
    version = "1.2.4"
  kubernetes {
    host                   = "https://${google_container_cluster.primary.endpoint}"
    insecure = false
    client_certificate     = "${base64decode(google_container_cluster.primary.master_auth.0.client_certificate)}"
    client_key             = "${base64decode(google_container_cluster.primary.master_auth.0.client_key)}"
    cluster_ca_certificate = "${base64decode(google_container_cluster.primary.master_auth.0.cluster_ca_certificate)}"
  }
}

provider kubernetes {
  version = "~> 1.9"
    host                   = "https://${google_container_cluster.primary.endpoint}"
    insecure = false
    client_certificate     = "${base64decode(google_container_cluster.primary.master_auth.0.client_certificate)}"
    client_key             = "${base64decode(google_container_cluster.primary.master_auth.0.client_key)}"
    cluster_ca_certificate = "${base64decode(google_container_cluster.primary.master_auth.0.cluster_ca_certificate)}"
  }

provider "local" {
  version = "~> 1.3"
}

provider "null" {
  version = "~> 2.1"
}

provider "template" {
  version = "~> 2.1"
}

#----------------------------------------------------------------------------------------------------

resource "google_compute_network" "vpc_network" {
  name = "gke-sql-network"
}

resource "google_compute_global_address" "private_ip_address" {
  name          = "private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc_network.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}


data "google_container_engine_versions" "main" {
  provider = google-beta
  project = var.project
  location = var.region
  version_prefix = "1.18."
}

resource "google_container_cluster" "primary" {
  name     = var.cluster
  location = var.region
  remove_default_node_pool = true
  initial_node_count = 1
  network    = google_compute_network.vpc_network.name

  cluster_autoscaling {
    enabled = true
    resource_limits{
        resource_type = "cpu"
        minimum = 5
        maximum = 10
    }
    resource_limits{
        resource_type = "memory"
        minimum = 3
        maximum = 5
    }
  }

    ip_allocation_policy {
        cluster_ipv4_cidr_block  = "/16"
        services_ipv4_cidr_block = "/22"
    }
    addons_config {
      horizontal_pod_autoscaling {
          disabled = true
    }

}

  master_auth {
    username = var.gke_username
    password = var.gke_password

    client_certificate_config {
      issue_client_certificate = false
    }
  }
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "${google_container_cluster.primary.name}-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = var.gke_num_nodes
  project    = var.project
  autoscaling{
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }
  upgrade_settings{
    max_unavailable = var.max_unavailable
    max_surge = var.max_surge
  }
  node_config {
      service_account = "350000048093-compute@developer.gserviceaccount.com"
    oauth_scopes = [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/sqlservice.admin"
    ]

    labels = {
      env = var.project
    }


    preemptible  = false
    machine_type = var.node_machine_type
    tags         = ["gke-node", "${var.project}-gke"]
    metadata = {
      disable-legacy-endpoints = "true"
    }

  }

    depends_on = [
        "google_container_cluster.primary",
    ]
}

#----------------------------------------------------------------------------------------------------

resource "null_resource" "gcloud" {
  depends_on = [google_container_node_pool.primary_nodes]
  provisioner "local-exec" {
    command = var.getClusterConfig
    working_dir = ".terraform"
  }
}

resource "null_resource" "create_letsencrypt_issuer" {
  depends_on = [null_resource.gcloud]

  provisioner "local-exec" {
    command     = "kubectl label ns default istio-injection=enabled"
    working_dir = ".terraform"
  }

  
}



resource "helm_release" "cert-manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  version    = "1.2.0"
  create_namespace = true
  timeout = 100

 set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [
    null_resource.create_letsencrypt_issuer,
  ]
  
}

resource "null_resource" "certmanager" {
  depends_on = [helm_release.cert-manager]

  provisioner "local-exec" {
    command     = "kubectl label ns cert-manager istio-injection=enabled"
    working_dir = ".terraform"
  }

  
}


resource "helm_release" "istio" {
  name       = "istio"
  chart      = "${var.homePath}/istio/istio_chart"
  namespace  = "istio-system"
  create_namespace = true
  depends_on = [
    null_resource.create_letsencrypt_issuer,
    
  ]
  
}

resource "null_resource" "istioenabled" {
  depends_on = [helm_release.istio]

  provisioner "local-exec" {
    command     = "kubectl label ns istio-system istio-injection=enabled"
    working_dir = ".terraform"
  }

  
}

resource "null_resource" "mtlsstrict" {
  depends_on = [null_resource.certmanager]
                                #"${var.project}-gke"
  provisioner "local-exec" {
    command     = "kubectl apply -f ${var.homePath}/istio/istio_addons/mtlsStrict.yaml"
    working_dir = ".terraform"
  }

  
}

data "kubernetes_service" "istio_ingress_gateway_elb" {
    depends_on = [
    helm_release.loggingstack,
    
  ]
    metadata {
        name        = "istio-ingressgateway"
        namespace   = "istio-system"
    }
}



resource "aws_route53_record" "elb" {
    
    allow_overwrite = true
    zone_id = var.zoneId
    name    = var.webappDomain
    type    = "A"
    ttl     = "300"
    records = [data.kubernetes_service.istio_ingress_gateway_elb.load_balancer_ingress.0.ip]
}

resource "helm_release" "istiocert" {
  depends_on = [
    aws_route53_record.elb,
    
  ]
  name       = "istiocert"
  chart      = "${var.homePath}/istio/ingress_cert"
 
  wait = true
  timeout = 100
  
}

locals {
  db_instance_creation_delay_factor_seconds = 45
}

resource "null_resource" "delayer_1" {
  depends_on = [helm_release.istiocert]

  provisioner "local-exec" {
    command = "echo creating ssl certificate && sleep ${local.db_instance_creation_delay_factor_seconds * 1}"
  }
}

resource "helm_release" "istiogateway" {
  name       = "istiogateway"
  chart      = "${var.homePath}/istio/ingress_gateway"
  depends_on = [
    null_resource.delayer_1,
    
  ]
  
}



resource "null_resource" "create_grafana_issuer" {
  depends_on = [helm_release.istiogateway]

  provisioner "local-exec" {
    command     = "kubectl apply -f ${var.homePath}/istio/istio_addons/grafana.yaml"
    working_dir = ".terraform"
  }

  
}

resource "null_resource" "create_prometheus_issuer" {
  depends_on = [helm_release.istiogateway]

  provisioner "local-exec" {
    command     = "kubectl apply -f ${var.homePath}/istio/istio_addons/prometheus.yaml"
    working_dir = ".terraform"
  }

  
}

resource "null_resource" "create_jaeger_issuer" {
  depends_on = [helm_release.istiogateway]

  provisioner "local-exec" {
    command     = "kubectl apply -f ${var.homePath}/istio/istio_addons/jaeger.yaml"
    working_dir = ".terraform"
  }

  
}

resource "null_resource" "create_kiali_issuer" {
  depends_on = [helm_release.istiogateway]

  provisioner "local-exec" {
    command     = "kubectl apply -f ${var.homePath}/istio/istio_addons/kiali.yaml"
    working_dir = ".terraform"
  }

  
}




# #-----------------------------------------------------------------------------------------

resource "random_id" "db_name_suffix" {
  byte_length = 4
}

resource "google_sql_database_instance" "webapp-instance" {
	   name = "webapp-instance-${random_id.db_name_suffix.hex}"
	   database_version = var.database_version
	   region = var.region
	   depends_on = [google_service_networking_connection.private_vpc_connection]
	   deletion_protection = "false"
	   settings {
	   		ip_configuration{
	   			ipv4_enabled = "false"
	   			private_network = google_compute_network.vpc_network.id
	   		}
	   		tier = var.dbtier
	   		activation_policy =  "ALWAYS"
	   		disk_autoresize = "false"
	   		disk_size = var.disk_size
	   }
}



resource "google_sql_user" "webapp-user" {
  name     = var.db_user
  password = var.db_password
  instance = google_sql_database_instance.webapp-instance.name  
}



resource "google_sql_database_instance" "beststories-instance" {
	   name = "beststories-instance-${random_id.db_name_suffix.hex}"
	   database_version = var.database_version
	   region = var.region
	   depends_on = [google_service_networking_connection.private_vpc_connection]
	   deletion_protection = "false"
	   settings {
	   		ip_configuration{
	   			ipv4_enabled = "false"
	   			private_network = google_compute_network.vpc_network.id
	   		}
	   		tier = var.dbtier
	   		activation_policy =  "ALWAYS"
	   		disk_autoresize = "false"
	   		disk_size = var.disk_size
	   }
}



resource "google_sql_user" "beststories-user" {
  name     = var.db_user
  password = var.db_password
  instance = google_sql_database_instance.beststories-instance.name  
}



resource "google_sql_database_instance" "topstories-instance" {
	   name = "topstories-instance-${random_id.db_name_suffix.hex}"
	   database_version = var.database_version
	   region = var.region
	   depends_on = [google_service_networking_connection.private_vpc_connection]
	   deletion_protection = "false"
	   settings {
	   		ip_configuration{
	   			ipv4_enabled = "false"
	   			private_network = google_compute_network.vpc_network.id
	   		}
	   		tier = var.dbtier
	   		activation_policy =  "ALWAYS"
	   		disk_autoresize = "false"
	   		disk_size = var.disk_size
	   }
}



resource "google_sql_user" "topstories-user" {
  name     = var.db_user
  password = var.db_password
  instance = google_sql_database_instance.topstories-instance.name  
}



resource "google_sql_database_instance" "newstories-instance" {
	   name = "newstories-instance-${random_id.db_name_suffix.hex}"
	   database_version = var.database_version
	   region = var.region
	   depends_on = [google_service_networking_connection.private_vpc_connection]
	   deletion_protection = "false"
	   settings {
	   		ip_configuration{
	   			ipv4_enabled = "false"
	   			private_network = google_compute_network.vpc_network.id
	   		}
	   		tier = var.dbtier
	   		activation_policy =  "ALWAYS"
	   		disk_autoresize = "false"
	   		disk_size = var.disk_size
	   }
}



resource "google_sql_user" "newstories-user" {
  name     = var.db_user
  password = var.db_password
  instance = google_sql_database_instance.newstories-instance.name  
}



resource "google_sql_database_instance" "notifier-instance" {
	   name = "notifier-instance-${random_id.db_name_suffix.hex}"
	   database_version = var.database_version
	   region = var.region
	   depends_on = [google_service_networking_connection.private_vpc_connection]
	   deletion_protection = "false"
	   settings {
	   		ip_configuration{
	   			ipv4_enabled = "false"
	   			private_network = google_compute_network.vpc_network.id
	   		}
	   		tier = var.dbtier
	   		activation_policy =  "ALWAYS"
	   		disk_autoresize = "false"
	   		disk_size = var.disk_size
	   }
}



resource "google_sql_user" "notifier-user" {
  name     = var.db_user
  password = var.db_password
  instance = google_sql_database_instance.notifier-instance.name  
}


# # ----------------------------------------------------------------------------------


resource "helm_release" "zookeeper" {
  name       = "zookeeper"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "zookeeper"

  values = [
    "${file("${var.homePath}/helm/zookeeper-values.yaml")}"
  ]
  depends_on = [
    helm_release.istio,
  ]
   
}



resource "null_resource" "kafka" {
  depends_on = [helm_release.zookeeper]

  provisioner "local-exec" {
    command     = "helm install kafka bitnami/kafka"
    working_dir = ".terraform"
  }
  
}

resource "helm_release" "elastic" {
  name       = "elastic"
  repository = "https://helm.elastic.co"
  chart      = "elasticsearch"

  values = [
    "${file("${var.homePath}/helm/elasticsearch-values.yaml")}"
  ]
  depends_on = [
    helm_release.istio,
  ]
  
}

resource "null_resource" "create_letsencrypt_issue" {
  depends_on = [helm_release.elastic]

  provisioner "local-exec" {
    command     = "kubectl create ns kube-logging"
    working_dir = ".terraform"
  }

  
}

resource "null_resource" "create_letsencrypt_issuer1" {
  depends_on = [null_resource.create_letsencrypt_issue]

  provisioner "local-exec" {
    command     = "kubectl label ns kube-logging istio-injection=enabled"
    working_dir = ".terraform"
  }

  
}

resource "helm_release" "loggingstack" {
  depends_on = [null_resource.create_letsencrypt_issuer1]
  name       = "loggingstack"
  chart      = "${var.homePath}/helm/helm-chart-efk/efk-chart"
}

resource "helm_release" "promkafkaexporter" {
  name       = "promkafka"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-kafka-exporter"

  values = [
    "${file("${var.homePath}/helm/prom-kafka-exporter-values.yaml")}"
  ]

  depends_on = [
    helm_release.istio,
  ]  
}

resource "helm_release" "promesexporter" {
  name       = "promes"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-elasticsearch-exporter"

  values = [
    "${file("${var.homePath}/helm/prom-es-exporter-values.yaml")}"
  ]
  depends_on = [
    helm_release.istio,
  ]
  
}

resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"

  values = [
    "${file("${var.homePath}/helm/prometheus-values.yaml")}"
  ]
  depends_on = [
    helm_release.istio,
  ]
  
}

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"

  values = [
    "${file("${var.homePath}/helm/grafana-values.yaml")}"
  ]
  depends_on = [
    helm_release.istio,
  ]
  
}
