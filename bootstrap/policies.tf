// bootstrap/policies.tf — Management-group scoped policy baseline for security and diagnostics

// Deny creation of public IP addresses at management group scope
resource "azurerm_policy_definition" "deny_public_ip" {
  name         = "deny-public-ip"
  display_name = "Deny Public IP Addresses"
  policy_type  = "Custom"
  mode         = "All"

  policy_rule = <<POLICY
{
  "if": {
    "field": "type",
    "equals": "Microsoft.Network/publicIPAddresses"
  },
  "then": {
    "effect": "deny"
  }
}
POLICY

  metadata = <<METADATA
{
  "category": "Network Security",
  "version": "1.0",
  "description": "Prevent creation of public IP addresses at management group scope to reduce exposure."
}
METADATA
}

// DeployIfNotExists: ensure diagnostic settings exist and forward logs to the central Log Analytics workspace
resource "azurerm_policy_definition" "deploy_diagnostic_settings" {
  name         = "deploy-diagnostic-settings-to-law"
  display_name = "Deploy Diagnostic Settings to Central Log Analytics Workspace"
  policy_type  = "Custom"
  mode         = "Indexed"

  policy_rule = <<POLICY
{
  "if": {
    "anyOf": [
      { "field": "type", "equals": "Microsoft.Compute/virtualMachines" },
      { "field": "type", "equals": "Microsoft.Storage/storageAccounts" },
      { "field": "type", "equals": "Microsoft.Network/networkInterfaces" },
      { "field": "type", "equals": "Microsoft.Network/networkSecurityGroups" }
    ]
  },
  "then": {
    "effect": "deployIfNotExists",
    "details": {
      "type": "Microsoft.Insights/diagnosticSettings",
      "roleDefinitionIds": [
        "/providers/microsoft.authorization/roleDefinitions/749f88d5-cbae-40b8-bcfc-e573ddc772fa"
      ],
      "existenceCondition": {
        "allOf": [
          { "field": "Microsoft.Insights/diagnosticSettings/workspaceId", "exists": "true" }
        ]
      },
      "deployment": {
        "properties": {
          "mode": "incremental",
          "template": {
            "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {
              "logAnalyticsWorkspaceId": { "type": "string" },
              "diagnosticName": { "type": "string" }
            },
            "resources": [
              {
                "type": "Microsoft.Insights/diagnosticSettings",
                "apiVersion": "2021-05-01-preview",
                "name": "[parameters('diagnosticName')]",
                "properties": {
                  "workspaceId": "[parameters('logAnalyticsWorkspaceId')]",
                  "logs": [ { "category": "Administrative", "enabled": true }, { "category": "Security", "enabled": true } ],
                  "metrics": [ { "category": "AllMetrics", "enabled": true } ]
                }
              }
            ]
          },
          "parameters": {
            "logAnalyticsWorkspaceId": {
              "value": "${azurerm_log_analytics_workspace.bootstrap_law.id}"
            },
            "diagnosticName": {
              "value": "platform-default"
            }
          }
        }
      }
    }
  }
}
POLICY

  metadata = <<METADATA
{
  "category": "Monitoring",
  "version": "1.0",
  "description": "Deploy diagnostic settings to common resource types so platform telemetry is centralized in the bootstrap Log Analytics workspace."
}
METADATA
}

// Assign the policies at the landing zones root management group
resource "azurerm_management_group_policy_assignment" "deny_public_ip_assignment" {
  name                 = "deny-public-ip-assignment"
  display_name         = "Deny Public IP Addresses Assignment"
  management_group_id  = azurerm_management_group.root.id
  policy_definition_id = azurerm_policy_definition.deny_public_ip.id
  description          = "Prevent creation of public IP addresses across landing zones."
}

resource "azurerm_management_group_policy_assignment" "deploy_diagnostic_settings_assignment" {
  name                 = "deploy-diagnostic-settings-assignment"
  display_name         = "Deploy Diagnostic Settings Assignment"
  management_group_id  = azurerm_management_group.root.id
  policy_definition_id = azurerm_policy_definition.deploy_diagnostic_settings.id
  description          = "Ensure supported resources send logs/metrics to the central Log Analytics workspace provisioning diagnostic settings when missing."

  // allow remediation tasks to be triggered from portal/automation (non-blocking)
  enforce = true
}
