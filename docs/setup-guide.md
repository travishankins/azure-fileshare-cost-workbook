# Azure File Share - Cost Per Share Workbook

## Overview

This workbook displays **estimated cost per file share** by distributing your storage account's billing costs proportionally based on each share's provisioned capacity.

It uses Cost Management API data ingested into Log Analytics, combined with Azure Monitor metrics for performance visibility.

---

## Included Files

| File | Description |
|------|-------------|
| `azure-fileshare-cost-workbook.json` | Workbook template (import into Azure Portal) |
| `dcr-schema-reference.json` | Data Collection Rule schema for the `AzureCostData_CL` table |

---

## Setup Steps

### Step 1: Create a Log Analytics Workspace

If you don't already have one:

```bash
az monitor log-analytics workspace create \
  --resource-group <your-rg> \
  --workspace-name <your-workspace-name> \
  --location <your-region>
```

### Step 2: Create a Data Collection Endpoint (DCE)

```bash
az monitor data-collection endpoint create \
  --name dce-cost-export \
  --resource-group <your-rg> \
  --location <your-region> \
  --public-network-access Enabled
```

### Step 3: Create a Data Collection Rule (DCR)

Create a file called `dcr-definition.json`:

```json
{
  "location": "<your-region>",
  "properties": {
    "dataCollectionEndpointId": "<your-dce-resource-id>",
    "streamDeclarations": {
      "Custom-AzureCostData_CL": {
        "columns": [
          { "name": "TimeGenerated", "type": "datetime" },
          { "name": "ResourceId", "type": "string" },
          { "name": "StorageAccountName", "type": "string" },
          { "name": "ShareName", "type": "string" },
          { "name": "MeterCategory", "type": "string" },
          { "name": "MeterName", "type": "string" },
          { "name": "CostValue", "type": "string" },
          { "name": "QuantityValue", "type": "string" },
          { "name": "Currency", "type": "string" },
          { "name": "UsageDate", "type": "string" }
        ]
      }
    },
    "destinations": {
      "logAnalytics": [
        {
          "workspaceResourceId": "<your-la-workspace-resource-id>",
          "name": "la-destination"
        }
      ]
    },
    "dataFlows": [
      {
        "streams": ["Custom-AzureCostData_CL"],
        "destinations": ["la-destination"],
        "transformKql": "source",
        "outputStream": "Custom-AzureCostData_CL"
      }
    ]
  }
}
```

Then create the DCR:

```bash
az monitor data-collection rule create \
  --name dcr-cost-export \
  --resource-group <your-rg> \
  --location <your-region> \
  --rule-file dcr-definition.json
```

### Step 4: Create the Cost Management Ingestion Logic App

This Logic App runs daily to query the Cost Management API and send data to Log Analytics.

1. **Create a Logic App** with a **System-Assigned Managed Identity**
2. **Assign roles** to the managed identity:
   - `Cost Management Reader` on the subscription
   - `Monitoring Metrics Publisher` on the DCR
3. **Configure the Logic App workflow:**
   - **Trigger:** Recurrence — daily at 6:00 AM
   - **Action 1:** HTTP — Query Cost Management API:
     ```
     POST https://management.azure.com/subscriptions/<sub-id>/providers/Microsoft.CostManagement/query?api-version=2023-11-01
     
     Body:
     {
       "type": "ActualCost",
       "timeframe": "MonthToDate",
       "dataset": {
         "granularity": "Daily",
         "aggregation": {
           "totalCost": { "name": "Cost", "function": "Sum" },
           "totalQuantity": { "name": "Quantity", "function": "Sum" }
         },
         "grouping": [
           { "type": "Dimension", "name": "ResourceId" },
           { "type": "Dimension", "name": "MeterCategory" },
           { "type": "Dimension", "name": "MeterName" }
         ],
         "filter": {
           "dimensions": {
             "name": "MeterCategory",
             "operator": "In",
             "values": ["Storage", "Files"]
           }
         }
       }
     }
     ```
   - **Action 2:** Parse and transform the response into the `AzureCostData_CL` schema
   - **Action 3:** HTTP — Send to DCE ingestion endpoint:
     ```
     POST https://<your-dce>.ingest.monitor.azure.com/dataCollectionRules/<dcr-immutable-id>/streams/Custom-AzureCostData_CL?api-version=2023-01-01
     ```

### Step 5: Enable Diagnostic Settings on Storage Account(s)

This sends per-share capacity and transaction metrics to Log Analytics (used by the Performance Metrics section of the workbook).

```bash
az monitor diagnostic-settings create \
  --name file-metrics-to-la \
  --resource "<storage-account-resource-id>/fileServices/default" \
  --workspace <your-la-workspace-resource-id> \
  --metrics '[{"category":"Capacity","enabled":true},{"category":"Transaction","enabled":true}]'
```

### Step 6: Import the Workbook

1. Go to **Azure Portal** → **Monitor** → **Workbooks**
2. Click **+ New**
3. Click the **Advanced Editor** button (`</>` icon in the toolbar)
4. Paste the contents of `azure-fileshare-cost-workbook.json`
5. Click **Apply**, then **Save**
6. Choose your subscription and resource group

### Step 7: Update Share Names in Workbook Queries

The workbook uses a `datatable` in each cost-per-share query to define your file shares. After importing, edit the workbook and update each query's `datatable` block with your actual share names and provisioned sizes:

```kusto
let ShareInfo = datatable(ShareName:string, StorageAccountName:string, ProvisionedGiB:real)
[
    "your-share-1", "yourstorageaccount", 100.0,
    "your-share-2", "yourstorageaccount", 500.0,
    "your-share-3", "yourstorageaccount", 1024.0
];
```

You can find your share names and sizes with:

```bash
az rest --method get \
  --url "https://management.azure.com/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<account>/fileServices/default/shares?api-version=2023-05-01" \
  --query "value[].{name:name, quotaGiB:properties.shareQuota}" \
  -o table
```

There are **3 queries** to update (look for `datatable` in each):
- Cost Per Share Summary
- Cost Per Share by Meter
- Month-over-Month Cost Per Share

### Step 8: Trigger the Logic App (or wait for the daily run)

```bash
az rest --method POST \
  --uri "https://management.azure.com/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Logic/workflows/<logic-app-name>/triggers/Recurrence/run?api-version=2016-06-01"
```

---

## Verifying Data

After the Logic App runs, verify data is in Log Analytics:

```bash
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "AzureCostData_CL | summarize count() by StorageAccountName | take 10" \
  -o table
```

---

## Workbook Sections

| Section | Data Source | Description |
|---------|-----------|-------------|
| Cost Per Share Summary | Log Analytics (`AzureCostData_CL`) | Tiles showing estimated cost per share |
| Cost Per Share by Meter | Log Analytics (`AzureCostData_CL`) | Breakdown by billing meter per share |
| Month-over-Month Comparison | Log Analytics (`AzureCostData_CL`) | Current vs previous month per share |
| Daily Cost Trend | Log Analytics (`AzureCostData_CL`) | Line chart of daily costs per share |
| Capacity Summary | Azure Monitor Metrics | Provisioned quota, used capacity, snapshots per share |
| Capacity Trend | Azure Monitor Metrics | 90-day provisioned capacity trend |
| Transactions / Egress / Ingress | Azure Monitor Metrics | Performance metrics per share |

---

## Notes

- Cost data from the Cost Management API can have up to a **24-hour delay**
- Azure Monitor metrics are **near real-time**
- For Premium File Storage, costs are directly proportional to provisioned capacity, making the proportional estimation accurate
- The `datatable` approach requires manual updates when shares are added/removed or resized — consider automating this via the Logic App in the future
