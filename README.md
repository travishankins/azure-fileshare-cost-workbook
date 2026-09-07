# Azure File Share Cost Workbook

Estimate per-share costs by allocating storage-account billing across file shares.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue?style=flat)](LICENSE)

[Quick Start](#quick-start) | [Configuration](#configuration) | [Validation](#validation) | [Guide](GUIDE.md)

## Overview

Bicep deploys cost ingestion into Log Analytics; a workbook allocates billing totals using configured share capacity.
These are allocation estimates, not authoritative per-share bills.

## Prerequisites

- A Premium FileStorage account in the intended deployment resource group.
- Azure deployment and role-assignment permissions, plus Cost Management access.
- Bicep tooling and Python 3.12 for workbook generation checks.

## Quick Start

```text
git clone https://github.com/travishankins/azure-fileshare-cost-workbook.git
cd azure-fileshare-cost-workbook
python scripts/build-workbook.py --check
```

Review the [project guide](GUIDE.md), configure share quotas, and preview the infrastructure before deploying.

## Configuration

Set the deployment inputs in [deploy/main.bicepparam](deploy/main.bicepparam).
Update share names and capacities in [queries/common.kql](queries/common.kql), then regenerate with `python scripts/build-workbook.py` before importing the workbook.

## Validation

Run the synchronization check above and compile [deploy/main.bicep](deploy/main.bicep).
Execute the queries and reconcile totals, currencies, reruns, and billing periods against source data before financial use.

## Operations

Queries use billing dates and deduplicate repeated imports. Preserve the previous workbook and billing history before updating.
Deploying a template does not correct old records with an incorrect currency label; those need a separate reviewed migration.

## Security and Limitations

Pagination and unexpected response columns are rejected rather than imported partially.
Current configured quotas do not form a historical capacity ledger; transactions, snapshots, and egress may not be proportional to capacity.
Currencies remain separate and are not converted.

## Documentation

- [Project guide](GUIDE.md): architecture, deployment, workbook import, and data schema.
- [Setup reference](docs/setup-guide.md): manual configuration details.
- [Query sources](queries/): readable workbook cost queries.

## Contributing

Open an issue or pull request with synthetic billing fixtures and reconciliation results. Never include private billing exports or customer identifiers.

## License

[MIT License](LICENSE).
