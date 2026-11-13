# nginx on Savannaa with Terraform

This example builds one Ubuntu VM on [Savannaa](https://savannaa.com) and installs nginx on it.
At the end you get a working web page on a public IP.

It uses the official Savannaa Terraform provider, [`savannaacloud/sws`](https://registry.terraform.io/providers/savannaacloud/sws).

## What it builds

| Resource | What it is |
|---|---|
| `sws_keypair` | Your SSH public key, uploaded to Savannaa |
| `sws_security_group` + 3 rules | A firewall group for SSH (22), HTTP (80) and HTTPS (443) |
| `sws_instance` | An Ubuntu 22.04 VM (`t3.micro`) with a public IP |
| `terraform_data` | Logs in to the VM over SSH and installs nginx |

## Before you start

You need:

1. **Terraform 1.4 or newer.** Check with `terraform version`.
2. **A Savannaa account.**
3. **A Savannaa API key.** In the console, go to **API & IaC → API Keys → Create API Key**.
   - Give it **Write** on **Compute** and **Network**. Read on the rest is fine.
   - Don't tick "All — full access".
   - Copy the key straight away (it starts with `ctk_`). It is shown only once.
4. **An SSH key pair** on your machine. By default it uses `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`.
   If you don't have one, run `ssh-keygen -t rsa -b 4096`.

## Quick start

```bash
# 1. Get the code
git clone <this-repo-url>
cd <repo-folder>

# 2. Give Terraform your API key (never put it in a file in this repo)
export SWS_API_KEY="ctk_your_key_here"

# 3. (Optional) Change the settings
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars

# 4. Build it
terraform init
terraform plan      # should say: 7 to add
terraform apply     # type: yes
```

The full run takes about 5 to 6 minutes. Most of that time is the VM finishing its first boot before nginx is installed.

At the end you will see:

```
ssh     = "ssh -i ~/.ssh/id_rsa ubuntu@<public-ip>"
website = "http://<public-ip>"
```

Open the `website` link. You should see **"Hello from Savannaa - deployed with Terraform"**.

## Settings

All settings have defaults, so `terraform.tfvars` is optional.

| Variable | Default | What it does |
|---|---|---|
| `region` | `ng-abuja-1` | Where to build: `ng-abuja-1` or `ng-lagos-1` |
| `instance_plan` | `t3.micro` | VM size. Free Tier accounts can only use `t2.micro` or `t3.micro` |
| `network_name` | `default` | Network to join. Every account gets one called `default` |
| `allowed_ssh_cidr` | `0.0.0.0/0` | Who may SSH in. Better: your own public IP + `/32` |
| `ssh_public_key_file` | `~/.ssh/id_rsa.pub` | Public key to upload |
| `ssh_private_key_file` | `~/.ssh/id_rsa` | Private key Terraform uses to log in and install nginx |

To find your public IP: `curl ifconfig.me`

## Clean up

To delete everything this example built:

```bash
terraform destroy
```

## Known limits (provider v0.5.3)

- **No startup script.** `sws_instance` has no `user_data` field. So nginx is installed over SSH after the VM boots, using Terraform's built-in `remote-exec`.
  This means the machine running Terraform must be able to reach the VM on port 22.
- **Firewall group is not attached.** `sws_instance` has no `security_groups` field.
  Terraform creates `nginx-demo-sg`, but you have to attach it to the VM yourself in the console.
  In our test, the platform's default rules already allowed SSH and HTTP, so it worked without attaching.
- **Free Tier sizes only.** On a Free Tier account, anything other than `t2.micro` or `t3.micro` fails with a `403`.

## Troubleshooting

| Error | Fix |
|---|---|
| `Missing API key` | Run `export SWS_API_KEY="ctk_..."` in the same terminal |
| `403 insufficient_scope` | Your API key is missing a Write scope. The error names it |
| `403 ... Only the SWS Free Tier instance types` | Set `instance_plan = "t3.micro"` |
| `Value for undeclared variable "region"` | Your `main.tf` is out of date. Pull the latest version |
| Install step stuck on "Connecting to remote host via SSH..." then times out | SSH is blocked. Attach `nginx-demo-sg` to the VM in the console, then run `terraform apply` again |
| Website won't load but apply worked | Port 80 is blocked. Attach `nginx-demo-sg` to the VM |

To check things on the VM itself:

```bash
ssh -i ~/.ssh/id_rsa ubuntu@<public-ip>
systemctl status nginx
cloud-init status --long
```

## Files

```
.
├── main.tf                    # everything: provider, firewall, VM, nginx install
├── terraform.tfvars.example   # copy to terraform.tfvars to change settings
├── .terraform.lock.hcl        # pins the provider version (keep this in Git)
├── .gitignore                 # keeps state files and secrets out of Git
└── README.md
```

## Security notes

- Never commit `terraform.tfstate`. It holds details of everything you built. `.gitignore` already excludes it.
- Never put your API key in `main.tf` or `terraform.tfvars`. Use the `SWS_API_KEY` environment variable.
- `allowed_ssh_cidr = "0.0.0.0/0"` is fine for a short test. For anything you keep, lock it to your own IP.
