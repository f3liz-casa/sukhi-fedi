terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.5"
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# ── Networking ────────────────────────────────────────────────────────────────
# Independent VCN/subnet from the ARM64 stack. Deploy into a separate
# compartment (or region) if you want both running side-by-side — same-
# compartment apply will collide on display_name uniqueness.

resource "oci_core_vcn" "sukhi_vcn" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = ["10.1.0.0/16"]
  display_name   = "sukhi-fedi-x64-vcn"
  dns_label      = "sukhix64"
}

resource "oci_core_internet_gateway" "sukhi_igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.sukhi_vcn.id
  display_name   = "sukhi-fedi-x64-igw"
  enabled        = true
}

resource "oci_core_route_table" "sukhi_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.sukhi_vcn.id
  display_name   = "sukhi-fedi-x64-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.sukhi_igw.id
  }
}

resource "oci_core_security_list" "sukhi_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.sukhi_vcn.id
  display_name   = "sukhi-fedi-x64-sl"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }

  # HTTP/HTTPS intentionally omitted — Cloudflare Tunnel handles all ingress
  # on this deployment (matches the ARM64 stack's posture).

  # ICMP for MTU path discovery
  ingress_security_rules {
    protocol = "1"
    source   = "0.0.0.0/0"
    icmp_options {
      type = 3
      code = 4
    }
  }
}

resource "oci_core_subnet" "sukhi_subnet" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.sukhi_vcn.id
  cidr_block                 = "10.1.1.0/24"
  display_name               = "sukhi-fedi-x64-subnet"
  dns_label                  = "prod"
  route_table_id             = oci_core_route_table.sukhi_rt.id
  security_list_ids          = [oci_core_security_list.sukhi_sl.id]
  prohibit_public_ip_on_vnic = false
}

# ── Compute Instance ──────────────────────────────────────────────────────────
# Always Free x64: VM.Standard.E2.1.Micro (1 OCPU, 1 GB RAM, fixed shape).
# Up to 2 of these allowed per tenancy on the Always Free tier.

data "oci_core_images" "ubuntu_amd" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.E2.1.Micro"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
  state                    = "AVAILABLE"
}

resource "oci_core_instance" "sukhi_vm" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_ocid
  shape               = "VM.Standard.E2.1.Micro"
  display_name        = var.instance_display_name

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_amd.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_size_gb
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.sukhi_subnet.id
    assign_public_ip = true
    display_name     = "sukhi-fedi-x64-vnic"
    hostname_label   = "sukhi-fedi-x64"
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)
    user_data = base64encode(templatefile("${path.module}/../cloud-init.yaml.tmpl", {
      ssh_public_key = trimspace(file(var.ssh_public_key_path))
      swap_mb        = 2048
      data_subdirs   = ["postgres", "nats"]
    }))
  }

  preserve_boot_volume = false
}

# ── Block Volume for persistent data ─────────────────────────────────────────
# Mount point /mnt/data is configured by cloud-init (infra/cloud-init.yaml.tmpl).
# PostgreSQL data → /mnt/data/postgres
# NATS JetStream  → /mnt/data/nats

resource "oci_core_volume" "sukhi_data_vol" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = "sukhi-fedi-x64-data"
  size_in_gbs         = var.block_volume_size_gb
  vpus_per_gb         = 10
}

resource "oci_core_volume_attachment" "sukhi_data_attach" {
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.sukhi_vm.id
  volume_id       = oci_core_volume.sukhi_data_vol.id
  display_name    = "sukhi-fedi-x64-data-attach"
}

# OCIR dynamic group / policy / container repo are intentionally NOT declared
# here — they live in the ARM64 stack (infra/terraform/main.tf) as tenancy-
# scoped resources. Re-creating them from this stack would collide on name.
# If you are deploying x64 without the ARM stack, copy those blocks over.
