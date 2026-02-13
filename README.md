# Azure File Share Cost Workbook

An Azure Workbook that shows **estimated cost per file share** — something Azure Cost Management doesn't provide natively.

Azure bills Premium File Storage at the storage account level. This workbook distributes that cost proportionally across individual file shares based on their provisioned capacity.

```
ShareCost = (ShareProvisionedGiB / TotalProvisionedGiB) × AccountTotalCost
```

## 📊 Workbook Sections

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

## 🏗️ Architecture

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

## 🚀 Quick Start

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

Edit the workbook and update the `datatable` block in each cost query with your file share names and sizes:

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

## 📁 Repository Structure

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

## 📋 Data Schema

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

## ⚠️ Important Notes

- **Cost data delay:** Cost Management API data can be up to 24 hours behind
- **Metrics are real-time:** Azure Monitor performance metrics are near real-time
- **Premium Files accuracy:** For Premium File Storage, cost is directly proportional to provisioned capacity, making the proportional estimate accurate
- **Share changes:** When you add, remove, or resize shares, update the `datatable` blocks in the workbook queries

## 🤝 Contributing

Contributions welcome! Please open an issue or PR.

## ⚖️ License

[MIT](LICENSE)
