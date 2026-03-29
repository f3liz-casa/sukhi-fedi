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

# Feed into downstream tooling:
#
#   Ansible inventory:
#     sed -i "s/<INSTANCE_PUBLIC_IP>/$(terraform output -raw instance_public_ip)/" \
#       ../../ansible/inventory.ini
#
#   Kamal deploy.yml:
#     sed -i "s/<INSTANCE_PUBLIC_IP>/$(terraform output -raw instance_public_ip)/g" \
#       ../../../config/deploy.yml ../../../config/deploy_deno.yml
