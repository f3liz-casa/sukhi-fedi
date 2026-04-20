output "instance_public_ip" {
  description = "Public IPv4 address of the sukhi-fedi VM"
  value       = oci_core_instance.sukhi_vm.public_ip
}

output "instance_private_ip" {
  description = "Private IPv4 address"
  value       = oci_core_instance.sukhi_vm.private_ip
}

output "instance_ocid" {
  description = "OCID of the compute instance"
  value       = oci_core_instance.sukhi_vm.id
}

output "data_volume_ocid" {
  description = "OCID of the attached block volume"
  value       = oci_core_volume.sukhi_data_vol.id
}

# ── Ansible inventory (auto-generated on apply) ───────────────────────────────

resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory.ini"
  file_permission = "0644"
  content         = <<-INI
    [sukhi_fedi]
    ${oci_core_instance.sukhi_vm.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_ed25519
  INI
}

