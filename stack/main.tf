# Polku BRouter server on Oracle Always Free (Ampere A1). Resource Manager fills
# tenancy_ocid, region and compartment_ocid itself. Apply again if Oracle says
# "Out of capacity": nothing is created until it succeeds.

terraform {
  required_providers {
    oci = { source = "oracle/oci" }
    tls = { source = "hashicorp/tls" }
  }
}

variable "tenancy_ocid" {}
variable "region" {}
variable "compartment_ocid" {}
variable "ocpus" { default = 1 }
variable "memory_gbs" { default = 6 }

provider "oci" {
  region = var.region
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_vcns" "polku" {
  compartment_id = var.compartment_ocid
  display_name   = "polku-vcn"
}

data "oci_core_subnets" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = data.oci_core_vcns.polku.virtual_networks[0].id
  display_name   = "public subnet-polku-vcn"
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
  filter {
    name   = "display_name"
    values = ["^Canonical-Ubuntu-24\\.04-aarch64-.*"]
    regex  = true
  }
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "oci_core_instance" "brouter" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "polku-brouter"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_gbs
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id
  }

  create_vnic_details {
    subnet_id        = data.oci_core_subnets.public.subnets[0].id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = tls_private_key.ssh.public_key_openssh
    user_data           = filebase64("${path.module}/cloud-init.sh")
  }
}

output "public_ip" {
  value = oci_core_instance.brouter.public_ip
}

output "brouter_url" {
  value = "https://${replace(oci_core_instance.brouter.public_ip, ".", "-")}.sslip.io/brouter"
}

output "ssh_private_key" {
  value     = tls_private_key.ssh.private_key_pem
  sensitive = true
}
