// ============================================================================
// Azure File Share Cost Workbook - Infrastructure Deployment
// ============================================================================

targetScope = 'resourceGroup'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Name prefix for all resources')
param namePrefix string = 'fscost'

@description('Resource ID of the Premium FileStorage account to monitor')
param storageAccountResourceId string

// ============================================================================
// Log Analytics Workspace
// ============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${namePrefix}-la'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 90
  }
}

// ============================================================================
// Data Collection Endpoint
// ============================================================================

resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' = {
  name: '${namePrefix}-dce'
  location: location
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

// ============================================================================
// Custom Log Table
// ============================================================================

resource costDataTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: logAnalyticsWorkspace
  name: 'AzureCostData_CL'
  properties: {
    schema: {
      name: 'AzureCostData_CL'
      columns: [
        { name: 'TimeGenerated', type: 'dateTime' }
        { name: 'ResourceId', type: 'string' }
        { name: 'StorageAccountName', type: 'string' }
        { name: 'ShareName', type: 'string' }
        { name: 'MeterCategory', type: 'string' }
        { name: 'MeterName', type: 'string' }
        { name: 'CostValue', type: 'string' }
        { name: 'QuantityValue', type: 'string' }
        { name: 'Currency', type: 'string' }
        { name: 'UsageDate', type: 'string' }
      ]
    }
    retentionInDays: 90
  }
}

// ============================================================================
// Data Collection Rule
// ============================================================================

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: '${namePrefix}-dcr'
  location: location
  dependsOn: [costDataTable]
  properties: {
    dataCollectionEndpointId: dataCollectionEndpoint.id
    streamDeclarations: {
      'Custom-AzureCostData_CL': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'ResourceId', type: 'string' }
          { name: 'StorageAccountName', type: 'string' }
          { name: 'ShareName', type: 'string' }
          { name: 'MeterCategory', type: 'string' }
          { name: 'MeterName', type: 'string' }
          { name: 'CostValue', type: 'string' }
          { name: 'QuantityValue', type: 'string' }
          { name: 'Currency', type: 'string' }
          { name: 'UsageDate', type: 'string' }
        ]
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspace.id
          name: 'la-destination'
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Custom-AzureCostData_CL']
        destinations: ['la-destination']
        transformKql: 'source'
        outputStream: 'Custom-AzureCostData_CL'
      }
    ]
  }
}

// ============================================================================
// Logic App - Cost Management Ingestion
// ============================================================================

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: '${namePrefix}-ingestion'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        subscriptionId: {
          defaultValue: subscription().subscriptionId
          type: 'String'
        }
        dceEndpoint: {
          defaultValue: dataCollectionEndpoint.properties.logsIngestion.endpoint
          type: 'String'
        }
        dcrImmutableId: {
          defaultValue: dataCollectionRule.properties.immutableId
          type: 'String'
        }
      }
      triggers: {
        Recurrence: {
          type: 'Recurrence'
          recurrence: {
            frequency: 'Day'
            interval: 1
            schedule: {
              hours: [6]
              minutes: [0]
            }
            timeZone: 'UTC'
          }
        }
      }
      actions: {
        Initialize_StartDate: {
          type: 'InitializeVariable'
          runAfter: {}
          inputs: {
            variables: [
              {
                name: 'StartDate'
                type: 'string'
                value: '@{formatDateTime(addDays(utcNow(), -30), \'yyyy-MM-dd\')}'
              }
            ]
          }
        }
        Initialize_EndDate: {
          type: 'InitializeVariable'
          runAfter: {
            Initialize_StartDate: ['Succeeded']
          }
          inputs: {
            variables: [
              {
                name: 'EndDate'
                type: 'string'
                value: '@{formatDateTime(utcNow(), \'yyyy-MM-dd\')}'
              }
            ]
          }
        }
        Initialize_AllRows: {
          type: 'InitializeVariable'
          runAfter: {
            Initialize_EndDate: ['Succeeded']
          }
          inputs: {
            variables: [
              {
                name: 'AllRows'
                type: 'array'
                value: []
              }
            ]
          }
        }
        Query_Cost_Management: {
          type: 'Http'
          runAfter: {
            Initialize_AllRows: ['Succeeded']
          }
          inputs: {
            method: 'POST'
            uri: 'https://management.azure.com/subscriptions/@{parameters(\'subscriptionId\')}/providers/Microsoft.CostManagement/query?api-version=2023-03-01'
            authentication: {
              type: 'ManagedServiceIdentity'
              audience: 'https://management.azure.com'
            }
            body: {
              type: 'ActualCost'
              timeframe: 'Custom'
              timePeriod: {
                from: '@{variables(\'StartDate\')}'
                to: '@{variables(\'EndDate\')}'
              }
              dataset: {
                granularity: 'Daily'
                aggregation: {
                  totalCost: { name: 'Cost', function: 'Sum' }
                  totalUsage: { name: 'UsageQuantity', function: 'Sum' }
                }
                grouping: [
                  { type: 'Dimension', name: 'ResourceId' }
                  { type: 'Dimension', name: 'MeterCategory' }
                  { type: 'Dimension', name: 'Meter' }
                ]
                filter: {
                  dimensions: {
                    name: 'MeterCategory'
                    operator: 'In'
                    values: ['Storage', 'Files', 'Azure Files', 'File Storage']
                  }
                }
              }
            }
          }
        }
        Build_Log_Records: {
          type: 'Foreach'
          runAfter: {
            Query_Cost_Management: ['Succeeded']
          }
          foreach: '@body(\'Query_Cost_Management\')?[\'properties\']?[\'rows\']'
          runtimeConfiguration: {
            concurrency: { repetitions: 50 }
          }
          actions: {
            Append_Record: {
              type: 'AppendToArrayVariable'
              inputs: {
                name: 'AllRows'
                value: {
                  TimeGenerated: '@{utcNow()}'
                  ResourceId: '@{items(\'Build_Log_Records\')[3]}'
                  StorageAccountName: '@{if(contains(toLower(string(items(\'Build_Log_Records\')[3])), \'storageaccounts/\'), first(split(last(split(toLower(string(items(\'Build_Log_Records\')[3])), \'storageaccounts/\')), \'/\')), \'\')}'
                  ShareName: '@{if(contains(toLower(string(items(\'Build_Log_Records\')[3])), \'/fileservices/default/shares/\'), last(split(toLower(string(items(\'Build_Log_Records\')[3])), \'/fileservices/default/shares/\')), \'\')}'
                  MeterCategory: '@{items(\'Build_Log_Records\')[4]}'
                  MeterName: '@{if(greater(length(items(\'Build_Log_Records\')), 5), items(\'Build_Log_Records\')[5], \'\')}'
                  CostValue: '@{string(items(\'Build_Log_Records\')[0])}'
                  QuantityValue: '@{string(items(\'Build_Log_Records\')[1])}'
                  Currency: 'USD'
                  UsageDate: '@{concat(substring(string(items(\'Build_Log_Records\')[2]), 0, 4), \'-\', substring(string(items(\'Build_Log_Records\')[2]), 4, 2), \'-\', substring(string(items(\'Build_Log_Records\')[2]), 6, 2))}'
                }
              }
            }
          }
        }
        Send_to_DCR: {
          type: 'Http'
          runAfter: {
            Build_Log_Records: ['Succeeded']
          }
          inputs: {
            method: 'POST'
            uri: '@{parameters(\'dceEndpoint\')}/dataCollectionRules/@{parameters(\'dcrImmutableId\')}/streams/Custom-AzureCostData_CL?api-version=2023-01-01'
            headers: {
              'Content-Type': 'application/json'
            }
            body: '@variables(\'AllRows\')'
            authentication: {
              type: 'ManagedServiceIdentity'
              audience: 'https://monitor.azure.com'
            }
          }
        }
      }
    }
  }
}

// ============================================================================
// Diagnostic Settings - File Service Metrics to Log Analytics
// ============================================================================

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${namePrefix}-file-metrics'
  scope: storageFileService
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      { category: 'Capacity', enabled: true }
      { category: 'Transaction', enabled: true }
    ]
  }
}

resource storageFileService 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' existing = {
  name: '${last(split(storageAccountResourceId, '/'))}/default'
}

// ============================================================================
// Role Assignments for Logic App Managed Identity
// ============================================================================

// Cost Management Reader on subscription
resource costManagementReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, logicApp.id, 'CostManagementReader')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '72fafb9e-0641-4937-9268-a91bfd8191a3')
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Monitoring Metrics Publisher on DCR
resource metricsPublisherRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataCollectionRule.id, logicApp.id, 'MonitoringMetricsPublisher')
  scope: dataCollectionRule
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Outputs
// ============================================================================

output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output dataCollectionEndpoint string = dataCollectionEndpoint.properties.logsIngestion.endpoint
output dataCollectionRuleImmutableId string = dataCollectionRule.properties.immutableId
output logicAppName string = logicApp.name
output logicAppPrincipalId string = logicApp.identity.principalId
