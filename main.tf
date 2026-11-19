terraform {
  required_version = ">= 1.4"
  required_providers {
    sws = { source = "savannaacloud/sws", version = "~> 0.5" }
  }
}

# The API key is read from the SWS_API_KEY environment variable.
# Never put the key in this file.
provider "sws" {
  region = var.region
}

variable "region" {
  type        = string
  description = "Savannaa region: ng-abuja-1 or ng-lagos-1."
  default     = "ng-abuja-1"
}

# One VM with nginx. sws_instance (v0.5.3) has no user_data and no
# security_groups field, so nginx is installed over SSH after boot.

variable "network_name" {
  type        = string
  description = "Existing network name. Every Savannaa account gets 'default'."
  default     = "default"
}

variable "allowed_ssh_cidr" {
  type        = string
  description = "Who may SSH in. Your public IP + /32, or 0.0.0.0/0 for a quick test."
  default     = "0.0.0.0/0"
}

variable "prefix" {
  type        = string
  description = "Start of every resource name. Change it to run more than one copy in the same account."
  default     = "nginx-demo"
}

variable "instance_plan" {
  type        = string
  description = "VM size. Free Tier accounts can only use t2.micro or t3.micro."
  default     = "t3.micro"
}

data "sws_network" "net" {
  name = var.network_name
}

variable "ssh_public_key_file" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_file" {
  type    = string
  default = "~/.ssh/id_rsa"
}

data "sws_image" "os" { name = "Ubuntu 22.04 LTS" }

resource "sws_keypair" "demo" {
  name       = var.prefix
  public_key = file(pathexpand(var.ssh_public_key_file))
}

# --- Firewall group -----------------------------------------------------
# Terraform creates it, but the provider cannot attach it to the VM yet.
# Attach it once in the Savannaa console (see notes in chat).

resource "sws_security_group" "web" {
  name        = "${var.prefix}-sg"
  description = "SSH from my IP, HTTP/HTTPS from anywhere"
}

resource "sws_security_group_rule" "ssh" {
  security_group_id = sws_security_group.web.id
  description       = "SSH from my IP"
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.allowed_ssh_cidr
}

resource "sws_security_group_rule" "http" {
  security_group_id = sws_security_group.web.id
  description       = "HTTP"
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "sws_security_group_rule" "https" {
  security_group_id = sws_security_group.web.id
  description       = "HTTPS"
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
}

# --- The VM ---------------------------------------------------------------

resource "sws_instance" "vm" {
  name       = "${var.prefix}-vm"
  plan       = var.instance_plan
  image      = data.sws_image.os.id
  network_id = data.sws_network.net.id
  keypair    = sws_keypair.demo.name
  public_ip  = true

  # Savannaa sometimes publishes a newer "Ubuntu 22.04 LTS" image under the
  # same name. Without this, Terraform would delete and rebuild the VM
  # every time that happens. New VMs still get the latest image.
  lifecycle {
    ignore_changes = [image]
  }
}

# --- Install nginx over SSH -------------------------------------------------

resource "terraform_data" "nginx" {
  # Re-run if the VM is replaced
  triggers_replace = [sws_instance.vm.id]

  connection {
    type        = "ssh"
    host        = sws_instance.vm.ip_address
    user        = sws_instance.vm.default_login_user
    private_key = file(pathexpand(var.ssh_private_key_file))
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cloud-init status --wait || true",
      "sudo apt-get update -y",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nginx",
      "echo '<h1>Hello from Savannaa - deployed with Terraform</h1>' | sudo tee /var/www/html/index.html",
      "sudo systemctl enable --now nginx",
      "curl -s -o /dev/null -w 'nginx local check: HTTP %%{http_code}\\n' http://localhost",
    ]
  }
}

output "ssh" {
  value = "ssh -i ${var.ssh_private_key_file} ${sws_instance.vm.default_login_user}@${sws_instance.vm.ip_address}"
}

output "website" {
  value = "http://${sws_instance.vm.ip_address}"
}

output "security_group_to_attach" {
  value = sws_security_group.web.name
}
