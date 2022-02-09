
#Provider & Auth statment
provider "google" {
    credentials = "${file("<jsonfilename>")}"
  project = "<myprojectid>"
  region  = "nortamerica-northeast2"
  zone    = "northamerica-northeast2-c"
}

# Virtual network
resource "google_compute_network" "Vnet1" {
  name                      = "vnet1"
  project                   = "myprojectid"
  provider                  = google-beta
  auto_create_subnetworks   = false
}

# Subnet for VM
resource "google_compute_subnetwork" "sub1" {
  name          = "subnet1"
  project       = google_compute_network.Vnet1.project
  provider      = google-beta
  ip_cidr_range = "10.0.1.0/24"
  region        = "nortamerica-northeast2"
  network       = google_compute_network.Vnet1.id
}

# Public IP address
resource "google_compute_global_address" "pip1" {
  provider      = google-beta
  project       = google_compute_network.Vnet1.id
  name          = "pip1"
}

# forwarding rule
resource "google_compute_global_forwarding_rule" "foward" {
  name                  = "forwarder"
  project               = google_compute_network.Vnet1.project
  provider              = google-beta
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.prox.id
  ip_address            = google_compute_global_address.pip1.id
}

# http proxy
resource "google_compute_target_http_proxy" "prox" {
  name               = "proxy"
  project            = google_compute_network.Vnet1.project
  provider           = google-beta
  url_map            = google_compute_url_map.url.id
}

# url mapping
resource "google_compute_url_map" "url" {
  name               = "urlmap"
  project            = google_compute_network.Vnet1.project
  provider           = google-beta
  default_service    = google_compute_backend_service.end.id
}

# backend service with custom request and response headers
resource "google_compute_backend_service" "end" {
  name                     = "backend"
  project                  = google_compute_network.Vnet1.project
  provider                 = google-beta
  protocol                 = "HTTP"
  port_name                = "http-port"
  load_balancing_scheme    = "EXTERNAL"
  timeout_sec              = 10
  enable_cdn               = true
  custom_request_headers   = ["X-Client-Geo-Location: {client_region_subdivision}, {client_city}"]
  custom_response_headers  = ["X-Cache-Hit: {cdn_cache_status}"]
  health_checks            = [google_compute_health_check.heal.id]
  backend {
    group           = google_compute_instance_group_manager.mig1.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

# Managed Instance Template
resource "google_compute_instance_template" "temp" {
  name          = "vm-template"
  project       = google_compute_network.Vnet1.project
  provider      = google-beta
  machine_type  = "e2-small"
  tags          = ["allow-health-check", "http-server"]

  network_interface {
    network    = google_compute_network.Vnet1.id
    subnetwork = google_compute_subnetwork.sub1.id
    access_config {
    }
  }
  disk {
    source_image = "debian-cloud/debian-10"
    auto_delete  = true
    boot         = true
  }
}

# health checker
resource "google_compute_health_check" "heal" {
  name      = "health-check"
  project   = google_compute_network.Vnet1.project
  provider  = google-beta
  http_health_check {
    port_specification = "USE_SERVING_PORT"
  }
}

# Managed Instance Group
resource "google_compute_instance_group_manager" "mig1" {
  name      = "managedinstance1"
  project   = google_compute_network.Vnet1.project
  provider  = google-beta
  zone      = "northamerica-northeast2-c"
  named_port {
    name = "http-port"
    port = 80
  }
  version {
    instance_template = google_compute_instance_template.temp.id
    name              = "primary"
  }
  base_instance_name = "vm"
  target_size        = 2
}

# Health Checker access
resource "google_compute_firewall" "fw" {
  name          = "firewall"
  project       = google_compute_network.Vnet1.project
  provider      = google-beta
  direction     = "INGRESS"
  network       = google_compute_network.Vnet1.id
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  allow {
    ports = ["80"]
    protocol = "tcp"
  }
  target_tags = ["allow-health-check", "http-server"]
}
