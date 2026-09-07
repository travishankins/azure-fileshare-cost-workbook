# Azure File Share Cost Workbook

## Status

An allocation estimate, not authoritative per-share billing. Bicep compilation
and generated-query synchronization are checked locally; live cost reconciliation
and KQL execution are required before using the totals for financial decisions.

## Verification

Run `python scripts/build-workbook.py --check`. Query sources are in `queries/`;
edit `queries/common.kql` for share names/quotas and regenerate with
`python scripts/build-workbook.py`. Queries use billing dates and the latest
import of each resource/date/meter/currency record rather than summing reruns.

## Limitations

The storage account must be in the deployment resource group. Response columns
must match the configured Cost Management query. Pagination is rejected explicitly
rather than ingesting partial totals; pagination support remains future work.
Shares use the configured current quota, not a historical quota ledger. Snapshot,
transaction, and egress costs need not be proportional to provisioned capacity.
Currency is retained and displayed separately; there is no currency conversion.

## Release and Rollback

Preview Bicep changes and retain the previous workbook before deployment. Reimport
the generated workbook after changing its query sources. Existing data produced
with an incorrect currency must be reconciled separately; template deployment
does not repair historical records. Do not delete billing history as a rollback.

An Azure Workbook that shows **estimated cost per file share** — something Azure Cost Management doesn't provide natively.

Azure bills Premium File Storage at the storage account level. This workbook distributes that cost proportionally across individual file shares based on their provisioned capacity.

```
ShareCost = (ShareProvisionedGiB / TotalProvisionedGiB) × AccountTotalCost
```

## Workbook Sections

| Section | Description |
|---------|-------------|
| **Cost Per Share Summary** | Tiles showing estimated monthly cost per share |
| **Cost Per Share by Meter** | Breakdown by billing meter (provisioned, snapshots, operations) |
| **Month-over-Month** | Current vs. previous month with trend indicators |
| **Daily Cost Trend** | Line chart of daily cost per share |
| **Capacity Summary** | Provisioned quota, used capacity, snapshots per share |
| **Capacity Trend** | 90-day provisioned capacity history |
| **Transactions / Egress / Ingress** | Performance metrics per share |

<!-- TODO: Add screenshot -->
<!-- ![Workbook Screenshot](docs/screenshot.png) -->

## Architecture

```
┌─────────────────────┐     ┌─────────────────────┐     ┌──────────────────┐
│  Cost Management API │────▶│  Logic App (daily)   │────▶│  Data Collection │
│  (billing data)      │     │  System Managed ID   │     │  Endpoint + Rule  │
└─────────────────────┘     └─────────────────────┘     └────────┬─────────┘
                                                                  │
                                                                  ▼
┌─────────────────────┐     ┌─────────────────────┐     ┌──────────────────┐
│  Azure Monitor       │────▶│  Diagnostic Settings │────▶│  Log Analytics    │
│  (capacity/perf)     │     │  (file svc metrics)  │     │  Workspace        │
└─────────────────────┘     └─────────────────────┘     └────────┬─────────┘
                                                                  │
                                                                  ▼
                                                         ┌──────────────────┐
                                                         │  Azure Workbook   │
                                                         │  (this template)  │
                                                         └──────────────────┘
```

## Quick Start

### Option 1: Bicep Deployment (Recommended)

Deploy all infrastructure with a single command:

```bash
# Clone the repo
git clone https://github.com/travishankins/azure-fileshare-cost-workbook.git
cd azure-fileshare-cost-workbook

# Edit the parameters
code deploy/main.bicepparam

# Deploy
az deployment group create \
  --resource-group <your-rg> \
  --template-file deploy/main.bicep \
  --parameters deploy/main.bicepparam
```

This creates:
- Log Analytics Workspace with `AzureCostData_CL` custom table
- Data Collection Endpoint + Rule
- Logic App with managed identity and role assignments
- Diagnostic settings on your storage account

Then import the workbook (see Step 2 below).

### Option 2: Manual Setup

See the [full setup guide](docs/setup-guide.md) for step-by-step CLI commands.

### Step 2: Import the Workbook

1. Go to **Azure Portal** → **Monitor** → **Workbooks**
2. Click **+ New**
3. Click the **Advanced Editor** button (`</>` icon)
4. Paste the contents of [`workbook/azure-fileshare-cost-workbook.json`](workbook/azure-fileshare-cost-workbook.json)
5. Click **Apply**, then **Save**

### Step 3: Configure Your Shares

Update the `datatable` in `queries/common.kql`, run the generator, then import the
updated workbook. Direct portal edits are not reflected in source control:

```kusto
let ShareInfo = datatable(ShareName:string, ProvisionedGiB:real)
[
    "myshare1", 100.0,
    "myshare2", 500.0,
    "myshare3", 1024.0
];
```

Find your shares with:

```bash
az rest --method get \
  --url "https://management.azure.com<your-storage-account-resource-id>/fileServices/default/shares?api-version=2023-05-01" \
  --query "value[].{name:name, GiB:properties.shareQuota}" -o table
```

### Step 4: Trigger Initial Data Load

```bash
# Run the Logic App manually (or wait for the 6 AM daily schedule)
az rest --method POST \
  --uri "https://management.azure.com/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Logic/workflows/<logic-app-name>/triggers/Recurrence/run?api-version=2016-06-01"
```

## Repository Structure

```
├── README.md
├── LICENSE
├── deploy/
│   ├── main.bicep              # Infrastructure-as-code (all resources)
│   └── main.bicepparam         # Deployment parameters
├── workbook/
│   └── azure-fileshare-cost-workbook.json  # Workbook template
└── docs/
    └── setup-guide.md          # Manual setup instructions
```

## Data Schema

The `AzureCostData_CL` custom table in Log Analytics:

| Column | Type | Description |
|--------|------|-------------|
| `TimeGenerated` | datetime | Ingestion timestamp |
| `StorageAccountName` | string | Storage account name |
| `ShareName` | string | File share name (if available) |
| `MeterCategory` | string | Billing meter category |
| `MeterName` | string | Billing meter name |
| `CostValue` | string | Pre-tax cost amount |
| `QuantityValue` | string | Usage quantity |
| `Currency` | string | Currency code |
| `UsageDate` | string | Date of usage (YYYY-MM-DD) |

## Important Notes

- **Cost data delay:** Cost Management API data can be up to 24 hours behind
- **Metrics are real-time:** Azure Monitor performance metrics are near real-time
- **Allocation accuracy:** Capacity-weighted allocation is an estimate and does not model each share's actual transactions, snapshots, egress, or historical quota changes
- **Share changes:** When you add, remove, or resize shares, update the `datatable` blocks in the workbook queries

## Contributing

Contributions welcome! Please open an issue or PR.

## License

[MIT](LICENSE)
