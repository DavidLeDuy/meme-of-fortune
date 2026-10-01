terraform {
  required_version = ">= 1.3.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.7.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# ------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------
variable "location" {
  type        = string
  default     = "switzerlandnorth"
  description = "Azure region for Resource Group & App Insights"
}

variable "swa_location" {
  type        = string
  default     = "westus2"
  description = "Azure region for Static Web App (supported SWA region and not locked like westeurope)"
}

variable "app_name" {
  type        = string
  default     = "memewheel"
  description = "Base name for deployed resources"
}

# ------------------------------------------------------------------------------
# Resource Group
# ------------------------------------------------------------------------------
resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.app_name}-prod"
  location = var.location
}

# ------------------------------------------------------------------------------
# Log Analytics Workspace
# ------------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-${var.app_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 1
}

# ------------------------------------------------------------------------------
# Application Insights
# ------------------------------------------------------------------------------
resource "azurerm_application_insights" "appinsights" {
  name                = "appinsights-${var.app_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  workspace_id        = azurerm_log_analytics_workspace.law.id
  application_type    = "web"
}

resource "azurerm_application_insights_workbook" "leaderboard_workbook" {
  name                = uuidv5("dns", "memewheel-leaderboard") # Workbook name must be a valid UUID
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  display_name        = "Meme Wheel Leaderboard Dashboard"
  source_id           = lower(azurerm_application_insights.appinsights.id)

  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        content = {
          json = "## Meme Wheel Player Leaderboard\nReal-time list of top connected players and their total spin counts."
        }
        name = "header"
      },
      {
        type = 3
        content = {
          version       = "KqlItem/1.0"
          query         = "customEvents\n| where name == \"MemeSpin\"\n| summarize TotalPulls = count() by PlayerName = tostring(customDimensions.PlayerName)\n| order by TotalPulls desc"
          size          = 0
          timeContext   = { durationMs = 86400000 } # Default filter to last 24h
          queryType     = 0
          resourceType  = "microsoft.insights/components"
          visualization = "table"
        }
        name = "player-spin-table"
      }
    ]
    isLocked = false
  })
}

# ------------------------------------------------------------------------------
# Azure Static Web App
# ------------------------------------------------------------------------------
resource "azurerm_static_web_app" "web" {
  name                = "stapp-${var.app_name}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.swa_location
  sku_tier            = "Free"
  sku_size            = "Free"
}

# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------
output "static_web_app_url" {
  description = "Live URL of your deployed application"
  value       = "https://${azurerm_static_web_app.web.default_host_name}"
}

output "app_insights_connection_string" {
  description = "Azure Application Insights Connection String"
  value       = azurerm_application_insights.appinsights.connection_string
  sensitive   = true
}

output "static_web_app_deployment_token" {
  description = "Deployment token for uploading website files"
  value       = azurerm_static_web_app.web.api_key
  sensitive   = true
}