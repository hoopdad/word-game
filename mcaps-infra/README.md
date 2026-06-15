# mcaps-infra

Generic spoke scaffold for the `mikeo-lab` hub.

## Current allocation

- **VNet CIDR:** `10.0.28.0/24`
- **Subnets:**
  - `workload-subnet` - `10.0.28.0/25`
  - `pep-subnet` - `10.0.28.128/26`

## What is included

- spoke resource group
- spoke VNet and subnet NSGs
- hub peering
- hub private DNS zone lookups
- hub Log Analytics and AMPLS lookups
- outputs for the spoke VNet, subnets, and hub references

## Hub follow-up

Apply the snippet in `_hub-todo/hub-dns-links.tf.snippet` after you have the spoke VNet ID.

## Next steps

```bash
cd mcaps-infra
terraform fmt -recursive
terraform init
terraform validate
terraform plan
```
